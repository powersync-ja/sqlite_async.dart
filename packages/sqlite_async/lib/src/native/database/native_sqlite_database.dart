import 'dart:async';
import 'dart:collection';
import 'dart:developer';
import 'dart:ffi';

import 'package:meta/meta.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_connection_pool/sqlite3_connection_pool.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/common/sqlite_database.dart';
import 'package:sqlite_async/src/native/native_sqlite_open_factory.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_options.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
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
class SqliteDatabaseImpl
    with SqliteQueries, SqliteDatabaseMixin
    implements SqliteDatabase {
  @override
  final DefaultSqliteOpenFactory openFactory;
  late final Future<SqliteConnectionPool> _pool =
      _openNativePool(openFactory, maxReaders);
  bool _isClosed = false;
  final _lockGuard = Object();

  @override
  final int maxReaders;

  @override
  @protected
  Future<void> get isInitialized => _pool;

  final Queue<IsolateWorker> _workers;

  @override
  late final Stream<UpdateNotification> updates = Stream.fromFuture(_pool)
      .asyncExpand((pool) => pool.updatedTables
          .map((changedTables) => UpdateNotification(changedTables.toSet())));

  /// Open a SqliteDatabase.
  ///
  /// A connection pool is used by default, allowing multiple concurrent read
  /// transactions, and a single concurrent write transaction. Write transactions
  /// do not block read transactions, and read transactions will see the state
  /// from the last committed write transaction.
  ///
  /// A maximum of [maxReaders] concurrent read transactions are allowed.
  factory SqliteDatabaseImpl(
      {required String path,
      int maxReaders = SqliteDatabase.defaultMaxReaders,
      SqliteOptions options = const SqliteOptions.defaults()}) {
    final factory =
        DefaultSqliteOpenFactory(path: path, sqliteOptions: options);
    return SqliteDatabaseImpl.withFactory(factory, maxReaders: maxReaders);
  }

  /// Advanced: Open a database with a specified factory.
  ///
  /// The factory is used to open each database connection in background isolates.
  ///
  /// Use when control is required over the opening process. Examples include:
  ///  1. Specifying the path to `libsqlite.so` on Linux.
  ///  2. Running additional per-connection PRAGMA statements on each connection.
  ///  3. Creating custom SQLite functions.
  ///  4. Creating temporary views or triggers.
  SqliteDatabaseImpl.withFactory(AbstractDefaultSqliteOpenFactory factory,
      {this.maxReaders = SqliteDatabase.defaultMaxReaders})
      : openFactory = factory as DefaultSqliteOpenFactory,
        // When the pool is fully used, we'd have all concurrent readers and a
        // writer operating on the database. Prepare a queue with that capacity.
        _workers = ListQueue(maxReaders + 1);

  @override
  bool get closed {
    return _isClosed;
  }

  /// Returns true if the _write_ connection is in auto-commit mode
  /// (no active transaction).
  @override
  Future<bool> getAutoCommit() async {
    _checkNotLocked('getAutoCommit');
    final pool = await _pool;
    final writer = await pool.writer();
    try {
      return await writer.autocommit;
    } finally {
      writer.returnLease();
    }
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    final pool = await _pool;
    pool.close();
  }

  /// Open a read-only transaction.
  ///
  /// Up to [maxReaders] read transactions can run concurrently.
  /// After that, read transactions are queued.
  ///
  /// Read transactions can run concurrently to a write transaction.
  ///
  /// Changes from any write transaction are not visible to read transactions
  /// started before it.
  @override
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout}) async {
    return _useConnection(
      writer: false,
      lockTimeout: lockTimeout,
      debugContext: 'readTransaction',
      (context) {
        return _transactionInLease(context, callback);
      },
    );
  }

  /// Open a read-write transaction.
  ///
  /// Only a single write transaction can run at a time - any concurrent
  /// transactions are queued.
  ///
  /// The write transaction is automatically committed when the callback finishes,
  /// or rolled back on any error.
  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) {
    return _useConnection(
      writer: true,
      lockTimeout: lockTimeout,
      debugContext: 'writeTransaction',
      (context) {
        return _transactionInLease(context, callback);
      },
    );
  }

  Future<T> _transactionInLease<T>(
    _LeasedContext context,
    Future<T> Function(SqliteWriteContext tx) callback,
  ) {
    final ctx = ScopedWriteContext(context);
    return ctx.writeTransaction(callback).whenComplete(ctx.invalidate);
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    return _useConnection(
      writer: false,
      debugContext: debugContext ?? 'readLock',
      lockTimeout: lockTimeout,
      (context) => ScopedReadContext.assumeReadLock(context, callback),
    );
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    return _useConnection(
      writer: true,
      debugContext: debugContext ?? 'writeLock',
      lockTimeout: lockTimeout,
      (context) => ScopedWriteContext.assumeWriteLock(context, callback),
    );
  }

  Future<T> _useConnection<T>(
    Future<T> Function(_LeasedContext context) callback, {
    required bool writer,
    required String debugContext,
    Duration? lockTimeout,
  }) {
    final timeout = lockTimeout?.asTimeout;
    return _runInLockContext(debugContext, () async {
      final pool = await _pool;
      final connection = await (writer
          ? pool.writer(abortSignal: timeout)
          : pool.reader(abortSignal: timeout));

      try {
        final context = _LeasedContext(
            inner: connection, pool: this, worker: await _takeIsolateWorker());
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
      final exclusiveAccess = await pool.exclusiveAccess();
      try {
        final writeExecutor = _LeasedContext(
          inner: exclusiveAccess.writer,
          pool: this,
          worker: await _takeIsolateWorker(),
        );
        final readExecutors = [
          for (final reader in exclusiveAccess.readers)
            _LeasedContext(
              inner: reader,
              pool: this,
              worker: await _takeIsolateWorker(),
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

  Future<IsolateWorker> _takeIsolateWorker() async {
    if (_workers.isEmpty) {
      return await IsolateWorker.spawn();
    } else {
      return _workers.removeFirst();
    }
  }

  void _returnIsolateWorker(IsolateWorker worker) {
    if (_isClosed) {
      worker.close();
    } else {
      _workers.addLast(worker);
    }
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

  T _runInLockContext<T>(String debugContext, T Function() inner) {
    _checkNotLocked(debugContext);
    return runZoned(inner, zoneValues: {_lockGuard: true});
  }

  static Future<SqliteConnectionPool> _openNativePool(
    DefaultSqliteOpenFactory openFactory,
    int maxReaders,
  ) {
    // We want to open pools asynchronously since running pragma statements as
    // part of openFactory.open might do IO. openAsync spawn a temporary isolate
    // for that.
    return SqliteConnectionPool.openAsync(
      name: openFactory.path,
      openConnections: () {
        Database openConnection({required bool isWriter}) {
          return openFactory.open(
            SqliteOpenOptions(primaryConnection: isWriter, readOnly: !isWriter),
          ) as Database;
        }

        return PoolConnections(
          openConnection(isWriter: true),
          [
            for (var i = 0; i < maxReaders; i++) openConnection(isWriter: false)
          ],
          // TODO: Option to enable prepared statement cache.
        );
      },
    );
  }
}

final class _LeasedContext extends UnscopedContext {
  final AsyncConnection inner;
  final SqliteDatabaseImpl pool;
  final TimelineTask? task;
  final IsolateWorker worker;

  /// Whether to throw an exception if we're about to execute a statement if
  /// the connection is in autocommit mode.
  final bool verifyInTransaction;

  @override
  bool closed = false;

  _LeasedContext({
    required this.inner,
    required this.pool,
    required this.worker,
    this.task,
    this.verifyInTransaction = false,
  });

  @override
  UnscopedContext interceptOutermostTransaction() {
    return _LeasedContext(
      inner: inner,
      pool: pool,
      worker: worker,
      task: task,
      verifyInTransaction: true,
    );
  }

  void close() {
    closed = true;
    pool._returnIsolateWorker(worker);
  }

  Future<T> _runOnWorker<T>(FutureOr<T> Function(PoolConnection db) compute) {
    return inner.unsafeAccess((connection) {
      final ptr = connection.unsafePointer.address;
      final checkInTransaction = verifyInTransaction;

      return worker.run(_wrapDbClosure(ptr, checkInTransaction, compute));
    });
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

  static T Function() _wrapDbClosure<T>(
      int ptr, bool checkInTransaction, T Function(PoolConnection) inner) {
    return () {
      // This pointer is safe: _wrapDbClosure is only called from within an
      // unsafeAccess block (so there's no concurrency). This call is also
      // awaited in the outer isolate, so the reference to the PoolConnection
      // stays alive until we've returned here.
      final conn = PoolConnection.unsafeFromPointer(Pointer.fromAddress(ptr));
      if (checkInTransaction) _checkInTransaction(conn.database);

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
