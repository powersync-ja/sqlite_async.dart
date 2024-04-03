import 'dart:async';
import 'dart:collection';

import 'mutex.dart';
import 'port_channel.dart';
import 'sqlite_connection.dart';
import 'sqlite_connection_impl.dart';
import 'sqlite_open_factory.dart';
import 'sqlite_queries.dart';
import 'update_notification.dart';

/// A connection pool with a single write connection and multiple read connections.
class SqliteConnectionPool with SqliteQueries implements SqliteConnection {
  SqliteConnection? _writeConnection;

  final Set<SqliteConnectionImpl> _allReadConnections = {};
  final Queue<SqliteConnectionImpl> _availableReadConnections = Queue();
  final Queue<_PendingItem> _queue = Queue();

  final SqliteOpenFactory _factory;
  final SerializedPortClient _upstreamPort;

  @override
  final Stream<UpdateNotification>? updates;

  final int maxReaders;

  final String? debugName;

  final Mutex mutex;

  @override
  bool closed = false;

  /// Open a new connection pool.
  ///
  /// The provided factory is used to open connections on demand. Connections
  /// are only opened when requested for the first time.
  ///
  /// [maxReaders] specifies the maximum number of read connections.
  /// A maximum of one write connection will be opened.
  ///
  /// Read connections are opened in read-only mode, and will reject any statements
  /// that modify the database.
  SqliteConnectionPool(this._factory,
      {this.updates,
      this.maxReaders = 5,
      SqliteConnection? writeConnection,
      this.debugName,
      required this.mutex,
      required SerializedPortClient upstreamPort})
      : _writeConnection = writeConnection,
        _upstreamPort = upstreamPort;

  /// Returns true if the _write_ connection is currently in autocommit mode.
  @override
  Future<bool> getAutoCommit() async {
    if (_writeConnection == null) {
      throw ClosedException();
    }
    return await _writeConnection!.getAutoCommit();
  }

  void _nextRead() {
    if (_queue.isEmpty) {
      // Wait for queue item
      return;
    } else if (closed) {
      while (_queue.isNotEmpty) {
        final nextItem = _queue.removeFirst();
        nextItem.completer.completeError(const ClosedException());
      }
      return;
    }

    while (_availableReadConnections.isNotEmpty &&
        _availableReadConnections.last.closed) {
      // Remove connections that may have errored
      final connection = _availableReadConnections.removeLast();
      _allReadConnections.remove(connection);
    }

    if (_availableReadConnections.isEmpty &&
        _allReadConnections.length == maxReaders) {
      // Wait for available connection
      return;
    }

    final nextItem = _queue.removeFirst();
    nextItem.completer.complete(Future.sync(() async {
      final nextConnection = _availableReadConnections.isEmpty
          ? await _expandPool()
          : _availableReadConnections.removeLast();
      try {
        final result = await nextConnection.readLock(nextItem.callback);
        return result;
      } finally {
        _availableReadConnections.add(nextConnection);
        _nextRead();
      }
    }));
  }

  @override
  Future<T> readLock<T>(ReadCallback<T> callback,
      {Duration? lockTimeout, String? debugContext}) async {
    if (closed) {
      throw ClosedException();
    }
    final zone = _getZone(debugContext: debugContext ?? 'get*()');
    final item = _PendingItem((ctx) {
      return zone.runUnary(callback, ctx);
    });
    _queue.add(item);
    _nextRead();

    return await item.completer.future;
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    if (closed) {
      throw ClosedException();
    }
    if (_writeConnection?.closed == true) {
      _writeConnection = null;
    }
    _writeConnection ??= SqliteConnectionImpl(
        upstreamPort: _upstreamPort,
        primary: false,
        updates: updates,
        debugName: debugName != null ? '$debugName-writer' : null,
        mutex: mutex,
        readOnly: false,
        openFactory: _factory);
    return _runZoned(() {
      return _writeConnection!.writeLock(callback,
          lockTimeout: lockTimeout, debugContext: debugContext);
    }, debugContext: debugContext ?? 'execute()');
  }

  /// The [Mutex] on individual connections do already error in recursive locks.
  ///
  /// We duplicate the same check here, to:
  /// 1. Also error when the recursive transaction is handled by a different
  ///    connection (with a different lock).
  /// 2. Give a more specific error message when it happens.
  T _runZoned<T>(T Function() callback, {required String debugContext}) {
    return _getZone(debugContext: debugContext).run(callback);
  }

  Zone _getZone({required String debugContext}) {
    if (Zone.current[this] != null) {
      throw LockError(
          'Recursive lock is not allowed. Use `tx.$debugContext` instead of `db.$debugContext`.');
    }
    return Zone.current.fork(zoneValues: {this: true});
  }

  Future<SqliteConnectionImpl> _expandPool() async {
    var name = debugName == null
        ? null
        : '$debugName-${_allReadConnections.length + 1}';
    var connection = SqliteConnectionImpl(
        upstreamPort: _upstreamPort,
        primary: false,
        updates: updates,
        debugName: name,
        mutex: mutex,
        readOnly: true,
        openFactory: _factory);
    _allReadConnections.add(connection);

    // Edge case:
    // If we don't await here, there is a chance that a different connection
    // is used for the transaction, and that it finishes and deletes the database
    // while this one is still opening. This is specifically triggered in tests.
    // To avoid that, we wait for the connection to be ready.
    await connection.ready;
    return connection;
  }

  @override
  Future<void> close() async {
    closed = true;

    // It is possible that `readLock()` removes connections from the pool while we're
    // closing connections, but not possible for new connections to be added.
    // Create a copy of the list, to avoid this triggering "Concurrent modification during iteration"
    final toClose = _allReadConnections.toList();
    for (var connection in toClose) {
      // Wait for connection initialization, so that any existing readLock()
      // requests go through before closing.
      await connection.ready;
      await connection.close();
    }
    // Closing the write connection cleans up the journal files (-shm and -wal files).
    // It can only do that if there are no other open connections, so we close the
    // read-only connections first.
    await _writeConnection?.close();
  }
}

typedef ReadCallback<T> = Future<T> Function(SqliteReadContext tx);

class _PendingItem {
  ReadCallback<dynamic> callback;
  Completer<dynamic> completer = Completer.sync();

  _PendingItem(this.callback);
}
