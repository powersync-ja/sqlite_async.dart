import 'dart:async';

import 'mutex.dart';
import 'port_channel.dart';
import 'sqlite_connection.dart';
import 'sqlite_connection_impl.dart';
import 'sqlite_open_factory.dart';
import 'sqlite_queries.dart';
import 'update_notification.dart';

/// A connection pool with a single write connection and multiple read connections.
class SqliteConnectionPool with SqliteQueries implements SqliteConnection {
  SqliteConnectionImpl? _writeConnection;

  final List<SqliteConnectionImpl> _readConnections = [];

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
      SqliteConnectionImpl? writeConnection,
      this.debugName,
      required this.mutex,
      required SerializedPortClient upstreamPort})
      : _writeConnection = writeConnection,
        _upstreamPort = upstreamPort;

  /// Returns true if the _write_ connection is currently in autocommit mode.
  @override
  Future<bool> getAutoCommit() async {
    if (_writeConnection == null) {
      throw AssertionError('Closed');
    }
    return await _writeConnection!.getAutoCommit();
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    await _expandPool();

    return _runZoned(() async {
      bool haveLock = false;
      var completer = Completer<T>();

      var futures = _readConnections.sublist(0).map((connection) async {
        if (connection.closed) {
          _readConnections.remove(connection);
        }
        try {
          return await connection.lock((ctx) async {
            if (haveLock) {
              // Already have a different lock - release this one.
              return false;
            }
            haveLock = true;

            var future = callback(ctx);
            completer.complete(future);

            // We have to wait for the future to complete before we can release the
            // lock.
            try {
              await future;
            } catch (_) {
              // Ignore
            }

            return true;
          },
              lockTimeout: lockTimeout,
              readOnly: true,
              debugContext: debugContext);
        } on TimeoutException {
          return false;
        }
      });

      final stream = Stream<bool>.fromFutures(futures);
      var gotAny = await stream.any((element) => element);

      if (!gotAny) {
        // All TimeoutExceptions
        throw TimeoutException('Failed to get a read connection', lockTimeout);
      }

      try {
        return await completer.future;
      } catch (e) {
        // throw e;
        rethrow;
      }
    }, debugContext: debugContext ?? 'get*()');
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    return _writeLock(callback,
        lockTimeout: lockTimeout, debugContext: debugContext, global: true);
  }

  Future<T> _writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext, required bool global}) {
    if (closed) {
      throw AssertionError('Closed');
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
      if (global) {
        // ignore: deprecated_member_use_from_same_package
        return _writeConnection!.writeLock(callback,
            lockTimeout: lockTimeout, debugContext: debugContext);
      } else {
        return _writeConnection!.lock(callback,
            lockTimeout: lockTimeout, debugContext: debugContext);
      }
    }, debugContext: debugContext ?? 'execute()');
  }

  @override
  Future<T> lock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {bool? readOnly, Duration? lockTimeout, String? debugContext}) {
    if (readOnly == true) {
      // ignore: deprecated_member_use_from_same_package
      return readLock((ctx) => callback(ctx as SqliteWriteContext),
          lockTimeout: lockTimeout, debugContext: debugContext);
    } else {
      // FIXME:
      // This should avoid using global locks, but then we need to fix
      // update notifications to only fire after commit.
      return _writeLock(callback,
          lockTimeout: lockTimeout, debugContext: debugContext, global: true);
    }
  }

  /// The [Mutex] on individual connections do already error in recursive locks.
  ///
  /// We duplicate the same check here, to:
  /// 1. Also error when the recursive transaction is handled by a different
  ///    connection (with a different lock).
  /// 2. Give a more specific error message when it happens.
  T _runZoned<T>(T Function() callback, {required String debugContext}) {
    if (Zone.current[this] != null) {
      throw LockError(
          'Recursive lock is not allowed. Use `tx.$debugContext` instead of `db.$debugContext`.');
    }
    var zone = Zone.current.fork(zoneValues: {this: true});
    return zone.run(callback);
  }

  Future<void> _expandPool() async {
    if (closed || _readConnections.length >= maxReaders) {
      return;
    }
    bool hasCapacity = _readConnections.any((connection) => !connection.locked);
    if (!hasCapacity) {
      var name = debugName == null
          ? null
          : '$debugName-${_readConnections.length + 1}';
      var connection = SqliteConnectionImpl(
          upstreamPort: _upstreamPort,
          primary: false,
          updates: updates,
          debugName: name,
          mutex: mutex,
          readOnly: true,
          openFactory: _factory);
      _readConnections.add(connection);

      // Edge case:
      // If we don't await here, there is a chance that a different connection
      // is used for the transaction, and that it finishes and deletes the database
      // while this one is still opening. This is specifically triggered in tests.
      // To avoid that, we wait for the connection to be ready.
      await connection.ready;
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    for (var connection in _readConnections) {
      await connection.close();
    }
    // Closing the write connection cleans up the journal files (-shm and -wal files).
    // It can only do that if there are no other open connections, so we close the
    // read-only connections first.
    await _writeConnection?.close();
  }
}
