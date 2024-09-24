import 'dart:async';
import 'dart:collection';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/src/native/database/native_sqlite_connection_impl.dart';
import 'package:sqlite_async/src/native/native_isolate_mutex.dart';

/// A connection pool with a single write connection and multiple read connections.
class SqliteConnectionPool with SqliteQueries implements SqliteConnection {
  final StreamController<UpdateNotification> updatesController =
      StreamController.broadcast();

  @override

  /// The write connection might be recreated if it's closed
  /// This will allow the update stream remain constant even
  /// after using a new write connection.
  late final Stream<UpdateNotification> updates = updatesController.stream;

  SqliteConnectionImpl? _writeConnection;

  final Set<SqliteConnectionImpl> _allReadConnections = {};
  final Queue<SqliteConnectionImpl> _availableReadConnections = Queue();
  final Queue<_PendingItem> _queue = Queue();

  final AbstractDefaultSqliteOpenFactory _factory;

  final int maxReaders;

  final String? debugName;

  final MutexImpl mutex;

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
      {this.maxReaders = 5,
      SqliteConnectionImpl? writeConnection,
      this.debugName,
      required this.mutex})
      : _writeConnection = writeConnection {
    // Use the write connection's updates
    _writeConnection?.updates?.forEach(updatesController.add);
  }

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

    var nextItem = _queue.removeFirst();
    while (nextItem.completer.isCompleted) {
      // This item already timed out - try the next one if available
      if (_queue.isEmpty) {
        return;
      }
      nextItem = _queue.removeFirst();
    }

    nextItem.lockTimer?.cancel();

    nextItem.completer.complete(Future.sync(() async {
      final nextConnection = _availableReadConnections.isEmpty
          ? await _expandPool()
          : _availableReadConnections.removeLast();
      try {
        // At this point the connection is expected to be available immediately.
        // No need to calculate a new lockTimeout here.
        final result = await nextConnection.readLock(nextItem.callback);
        return result;
      } finally {
        _availableReadConnections.add(nextConnection);
        Timer.run(_nextRead);
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
    }, lockTimeout: lockTimeout);
    _queue.add(item);
    _nextRead();

    return (await item.future) as T;
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    if (closed) {
      throw ClosedException();
    }
    if (_writeConnection?.closed == true) {
      _writeConnection = null;
    }

    if (_writeConnection == null) {
      _writeConnection = (await _factory.openConnection(SqliteOpenOptions(
          primaryConnection: true,
          debugName: debugName != null ? '$debugName-writer' : null,
          mutex: mutex,
          readOnly: false))) as SqliteConnectionImpl;
      // Expose the new updates on the connection pool
      _writeConnection!.updates?.forEach(updatesController.add);
    }

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
        upstreamPort: upstreamPort,
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

  SerializedPortClient? get upstreamPort {
    return _writeConnection?.upstreamPort;
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

  @override
  Future<void> refreshSchema() async {
    final toRefresh = _allReadConnections.toList();

    await _writeConnection?.refreshSchema();

    for (var connection in toRefresh) {
      await connection.refreshSchema();
    }
  }

  List<SqliteConnection> getAllConnections() {
    final connections = <SqliteConnection>[];
    if (_writeConnection != null) {
      connections.add(_writeConnection!);
    }
    connections.addAll(_allReadConnections);
    return connections;
  }

  int getNumConnections() {
    print(
        "TESTING READ: ${_allReadConnections.length} WRITE: ${_writeConnection == null ? 0 : 1}");
    return _allReadConnections.length + (_writeConnection == null ? 0 : 1);
  }
}

typedef ReadCallback<T> = Future<T> Function(SqliteReadContext tx);

class _PendingItem {
  ReadCallback<dynamic> callback;
  Completer<dynamic> completer = Completer.sync();
  late Future<dynamic> future = completer.future;
  DateTime? deadline;
  final Duration? lockTimeout;
  late final Timer? lockTimer;

  _PendingItem(this.callback, {this.lockTimeout}) {
    if (lockTimeout != null) {
      deadline = DateTime.now().add(lockTimeout!);
      lockTimer = Timer(lockTimeout!, () {
        // Note: isCompleted is true when `nextItem.completer.complete` is called, not when the result is available.
        // This matches the behavior we need for a timeout on the lock, but not the entire operation.
        if (!completer.isCompleted) {
          // completer.completeError(
          //     TimeoutException('Failed to get a read connection', lockTimeout));
          completer.complete(Future.sync(() async {
            throw TimeoutException(
                'Failed to get a read connection', lockTimeout);
          }));
        }
      });
    } else {
      lockTimer = null;
    }
  }
}
