import 'dart:async';
import 'dart:collection';
import 'dart:developer';

import 'package:meta/meta.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_connection_pool/sqlite3_connection_pool.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/common/sqlite_database.dart';
import 'package:sqlite_async/src/native/native_sqlite_open_factory.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';

import 'package:sqlite_async/src/update_notification.dart';

import '../../common/mutex.dart';
import '../../common/timeouts.dart';
import '../../impl/context.dart';
import '../../utils/profiler.dart';
import 'worker.dart';

/// A SQLite database instance.
///
/// It is safe to use multiple instances backed by the same database file. In
/// that case, update notifications and connection locks are automatically
/// shared between instances. This also works if the instances are opened on
/// different isolates or Dart/Flutter engines in the same process without prior
/// coordination.
final class NativeSqliteDatabaseImpl extends SqliteDatabaseImpl {
  @override
  final NativeSqliteOpenFactory openFactory;
  late final Future<SqliteConnectionPool> _pool =
      _openNativePool(openFactory).then((pool) {
    // Pipe updates into a stream controller as soon as the pool is opened to
    // avoid missing updates if the stream is only listened to later.
    _updates.addStream(pool.updatedTables.map((e) {
      return UpdateNotification(e.toSet());
    }));

    return pool;
  });
  Future<void>? _closing;
  final _lockGuard = Object();
  int _activeOperations = 0;
  Completer<void>? _operationsDrained;

  @override
  int get maxReaders => openFactory.sqliteOptions.maxReaders;

  @override
  @protected
  Future<void> get isInitialized => _pool;

  final _Executors _executors;

  final StreamController<UpdateNotification> _updates =
      StreamController.broadcast(sync: true);

  @override
  Stream<UpdateNotification> get updates => _updates.stream;

  NativeSqliteDatabaseImpl(this.openFactory)
      : _executors = openFactory.sqliteOptions.useBackgroundIsolates
            ? _IsolateExecutors(openFactory.sqliteOptions.maxReaders)
            : const _SynchronousExecutors();

  @override
  bool get closed {
    return _closing != null;
  }

  /// Returns true if the _write_ connection is in auto-commit mode
  /// (no active transaction).
  @override
  Future<bool> getAutoCommit() => _useConnection(
        (context) => context.getAutoCommit(),
        writer: true,
        debugContext: 'getAutoCommit',
      );

  @override
  Future<void> close() {
    _checkNotLocked('close');

    return _closing ??= Future.sync(() async {
      final pool = await _pool;

      // Avoid exclusive access because another Dart instance can use this pool.
      await [
        pool.close(abortOutstandingRequests: true),
        if (_activeOperations > 0)
          (_operationsDrained ??= Completer<void>()).future,
      ].wait;
      // Active operations return their workers before shutdown closes them.
      await _executors.close();
    });
  }

  @override
  Future<T> abortableReadLock<T>(
      Future<T> Function(SqliteReadContext tx) callback,
      {Future<void>? abortTrigger,
      String? debugContext}) async {
    return _useConnection(
      writer: false,
      debugContext: debugContext ?? 'readLock',
      abortTrigger: abortTrigger,
      (context) => ScopedReadContext.assumeReadLock(context, callback),
    );
  }

  @override
  Future<T> abortableWriteLock<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Future<void>? abortTrigger,
      String? debugContext}) async {
    return _useConnection(
      writer: true,
      debugContext: debugContext ?? 'writeLock',
      abortTrigger: abortTrigger,
      (context) => ScopedWriteContext.assumeWriteLock(context, callback),
    );
  }

  Future<T> _useConnection<T>(
    Future<T> Function(_LeasedContext context) callback, {
    required bool writer,
    required String debugContext,
    Future<void>? abortTrigger,
  }) {
    return _runInLockContext(debugContext, () async {
      final pool = await _pool;
      final connection = await (writer
              ? pool.writer(abortSignal: abortTrigger)
              : pool.reader(abortSignal: abortTrigger))
          .translateAbortExceptions(debugContext);

      try {
        final context = _LeasedContext(
            inner: connection, executor: await _executors.take());
        try {
          return await callback(context);
        } finally {
          context.close();
        }
      } finally {
        connection.returnLease();
      }
    });
  }

  @override
  Future<void> refreshSchema() async {
    _checkNotLocked('refreshSchema');
    await withAllConnections((writer, readers) async {
      await Future.wait([
        writer.execute("PRAGMA table_info('sqlite_master')"),
        for (final reader in readers)
          reader.getAll("PRAGMA table_info('sqlite_master')")
      ]);
    });
  }

  @override
  Future<T> withAllConnections<T>(
      Future<T> Function(
              SqliteWriteContext writer, List<SqliteReadContext> readers)
          block) async {
    final pool = await _pool;
    return _runInLockContext('withAllConnections', () async {
      final exclusiveAccess = await pool
          .exclusiveAccess()
          .translateAbortExceptions('withAllConnections');
      try {
        final writeExecutor = _LeasedContext(
          inner: exclusiveAccess.writer,
          executor: await _executors.take(),
        );
        final readExecutors = [
          for (final reader in exclusiveAccess.readers)
            _LeasedContext(
              inner: reader,
              executor: await _executors.take(),
            )
        ];
        final writer = ScopedWriteContext(writeExecutor);
        final readers = [
          for (final reader in readExecutors) ScopedReadContext(reader)
        ];

        try {
          return await block(writer, readers);
        } finally {
          writeExecutor.close();
          for (final reader in readExecutors) {
            reader.close();
          }

          writer.invalidate();
          for (final reader in readers) {
            reader.invalidate();
          }
        }
      } finally {
        exclusiveAccess.close();
      }
    });
  }

  @override
  Future<ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return _useConnection(debugContext: 'execute', writer: true, (ctx) async {
      final rs = await ctx.execute(sql, parameters);
      await ctx.checkNotInTransaction();
      return rs;
    });
  }

  void _checkNotLocked(String? debugContext) {
    if (Zone.current[_lockGuard] != null) {
      var message =
          'Blocked attempt to use connection object in a read/write lock callback.';
      if (debugContext != null) {
        message +=
            ' Try using `tx.$debugContext` instead of `db.$debugContext`.';
      }

      throw LockError(message);
    }
  }

  Future<T> _runInLockContext<T>(
      String debugContext, Future<T> Function() inner) {
    _checkNotLocked(debugContext);
    if (closed) return Future.error(AbortException(debugContext));
    _activeOperations++;
    return runZoned(() async {
      try {
        return await inner();
      } finally {
        _activeOperations--;
        if (_activeOperations == 0) _operationsDrained?.complete();
      }
    }, zoneValues: {_lockGuard: true});
  }

  static Future<SqliteConnectionPool> _openNativePool(
    NativeSqliteOpenFactory openFactory,
  ) async {
    await openFactory.beforeOpen();

    final maxReaders = openFactory.sqliteOptions.maxReaders;

    PoolConnections openConnections() =>
        _openPoolConnections(openFactory, maxReaders);

    if (openFactory.sqliteOptions.useBackgroundIsolates) {
      // We want to open pools asynchronously since running pragma statements as
      // part of openFactory.open might do IO. openAsync spawn a temporary
      // isolate for that.
      return await SqliteConnectionPool.openAsync(
          name: openFactory.path, openConnections: openConnections);
    } else {
      return SqliteConnectionPool.open(
          name: openFactory.path, openConnections: openConnections);
    }
  }

  static PoolConnections _openPoolConnections(
      NativeSqliteOpenFactory openFactory, int maxReaders) {
    Database openConnection({required bool isWriter}) {
      return openFactory.openNativeConnection(
        SqliteOpenOptions(primaryConnection: isWriter, readOnly: !isWriter),
      );
    }

    return PoolConnections(
      openConnection(isWriter: true),
      [for (var i = 0; i < maxReaders; i++) openConnection(isWriter: false)],
      preparedStatementCacheSize:
          openFactory.sqliteOptions.preparedStatementCacheSize,
    );
  }
}

/// Hands out [_Executor]s used to run statements on leased connections.
sealed class _Executors {
  const _Executors();

  FutureOr<_Executor> take();

  Future<void> close();
}

abstract interface class _Executor {
  /// Runs [compute] on [connection], which must be obtained from an
  /// [AsyncConnection.unsafeAccess] call on [inner].
  Future<T> run<T>(AsyncConnection inner, PoolConnection connection,
      FutureOr<T> Function(PoolConnection) compute);

  /// Makes this executor available to other connections again.
  void release();
}

final class _SynchronousExecutors extends _Executors implements _Executor {
  const _SynchronousExecutors();

  @override
  _Executor take() => this;

  @override
  Future<void> close() async {}

  @override
  Future<T> run<T>(AsyncConnection inner, PoolConnection connection,
      FutureOr<T> Function(PoolConnection) compute) async {
    return await compute(connection);
  }

  @override
  void release() {}
}

/// Runs statements on a pool of long-lived background isolates.
final class _IsolateExecutors extends _Executors {
  final Queue<IsolateWorker> _workers;

  _IsolateExecutors(int maxReaders)
      // When the pool is fully used, we'd have all concurrent readers and a
      // writer operating on the database. Prepare a queue with that capacity.
      : _workers = ListQueue(maxReaders + 1);

  @override
  FutureOr<_Executor> take() {
    if (_workers.isEmpty) {
      return IsolateWorker.spawn().then((w) => _IsolateExecutor(this, w));
    } else {
      return _IsolateExecutor(this, _workers.removeFirst());
    }
  }

  @override
  Future<void> close() async {
    await _workers.map((e) => e.close()).wait;
  }
}

final class _IsolateExecutor implements _Executor {
  final _IsolateExecutors _owner;
  final IsolateWorker _worker;

  _IsolateExecutor(this._owner, this._worker);

  @override
  Future<T> run<T>(AsyncConnection inner, PoolConnection connection,
      FutureOr<T> Function(PoolConnection) compute) {
    return _worker.run(inner.shareableConnection, compute);
  }

  @override
  void release() => _owner._workers.addLast(_worker);
}

final class _LeasedContext extends UnscopedContext {
  final AsyncConnection inner;
  final TimelineTask? task;
  final _Executor executor;

  /// Whether to throw an exception if we're about to execute a statement if
  /// the connection is in autocommit mode.
  final bool verifyInTransaction;

  @override
  bool closed = false;

  _LeasedContext({
    required this.inner,
    required this.executor,
    this.task,
    this.verifyInTransaction = false,
  });

  @override
  UnscopedContext interceptOutermostTransaction() {
    return _LeasedContext(
      inner: inner,
      executor: executor,
      task: task,
      verifyInTransaction: true,
    );
  }

  void close() {
    closed = true;
    executor.release();
  }

  Future<T> _runOnWorker<T>(
      FutureOr<T> Function(PoolConnection db) compute) async {
    final (result, autocommit) = await inner.unsafeAccess((connection) async {
      final result = await executor.run(inner, connection,
          verifyInTransaction ? _checkingInTransaction(compute) : compute);

      return (result, connection.database.autocommit);
    });

    if (autocommit) {
      if (inner case final ConnectionLease lease) {
        await lease.notifyUpdates();
      }
    }

    return result;
  }

  @override
  Future<T> computeWithDatabase<T>(
      FutureOr<T> Function(CommonDatabase db) compute) {
    return _runOnWorker((db) => compute(db.database));
  }

  @override
  Future<ResultSet> execute(String sql, List<Object?> parameters) {
    return task.timeAsync('execute', sql: sql, parameters: parameters, () {
      return _runOnWorker(_select(sql, parameters));
    });
  }

  @override
  Future<void> executeBatch(String sql, List<dynamic> parameterSets) {
    // TODO: Make parameterSets a List<List<Object?>>
    return task.timeAsync('executeMultiple', sql: sql, () {
      return _runOnWorker(_executeBatch(sql, parameterSets));
    });
  }

  @override
  Future<void> executeMultiple(String sql) {
    return task.timeAsync('executeMultiple', sql: sql, () {
      return _runOnWorker(_selectMultiple(sql));
    });
  }

  @override
  Future<ResultSet> getAll(String sql, [List<Object?> parameters = const []]) {
    return execute(sql, parameters);
  }

  @override
  Future<bool> getAutoCommit() {
    return inner.autocommit;
  }

  static void _checkInTransaction(CommonDatabase db) {
    if (db.autocommit) {
      throw SqliteException(
        extendedResultCode: 0,
        message: 'Transaction rolled back by earlier statement',
      );
    }
  }

  // Static helper methods to create closures we can send across isolates.

  static FutureOr<T> Function(PoolConnection) _checkingInTransaction<T>(
      FutureOr<T> Function(PoolConnection) inner) {
    return (conn) {
      _checkInTransaction(conn.database);
      return inner(conn);
    };
  }

  static ResultSet Function(PoolConnection) _select(
      String sql, List<Object?> parameters) {
    return (db) => db.select(sql, parameters);
  }

  static void Function(PoolConnection) _executeBatch(
      String sql, List<dynamic> parameterSets) {
    return (conn) {
      final stmt = conn.database.prepare(sql, checkNoTail: true);
      try {
        for (final instantiation in parameterSets) {
          stmt.execute(instantiation);
        }
      } finally {
        stmt.close();
      }
    };
  }

  static void Function(PoolConnection) _selectMultiple(String sql) {
    return (db) => db.execute(sql);
  }
}

extension<T> on Future<T> {
  Future<T> translateAbortExceptions(String debugContext) {
    return onError<PoolAbortException>(
        (e, s) => Error.throwWithStackTrace(AbortException(debugContext), s));
  }
}
