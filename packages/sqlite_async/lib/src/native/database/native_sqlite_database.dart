import 'dart:async';

import 'package:meta/meta.dart';
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
import 'leased_context.dart';

/// A SQLite database instance.
///
/// It is safe to use multiple instances backed by the same database file. In
/// that case, update notifications and connection locks are automatically
/// shared between instances. This also works if the instances are opened on
/// different
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

  @override
  late final Stream<UpdateNotification> updates = Stream.fromFuture(_pool)
      .asyncExpand((pool) => pool.updatedTables
          .map((changedTables) => UpdateNotification(changedTables.toSet())));

  /// Open a SqliteDatabase.
  ///
  /// Only a single SqliteDatabase per [path] should be opened at a time.
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
      : openFactory = factory as DefaultSqliteOpenFactory;

  @override
  bool get closed {
    return _isClosed;
  }

  /// Returns true if the _write_ connection is in auto-commit mode
  /// (no active transaction).
  @override
  Future<bool> getAutoCommit() async {
    _checkNotLocked();
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
    final pool = await _pool;
    return _runInLockContext(() async {
      final reader = await pool.reader(abortSignal: lockTimeout?.asTimeout);
      try {
        // We pretend this is a write context to be able to use the connection
        // helper. This doesn't matter much since attempting to do a write here
        // would throw.
        return await ScopedWriteContext.assumeWriteLock(LeasedContext(reader),
            (context) {
          return context.writeTransaction(callback);
        });
      } finally {
        reader.returnLease();
      }
    });
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
    return writeLock((context) {
      return context.writeTransaction(callback);
    }, lockTimeout: lockTimeout);
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    final pool = await _pool;
    return _runInLockContext(() async {
      final reader = await pool.reader(abortSignal: lockTimeout?.asTimeout);
      try {
        return await ScopedReadContext.assumeReadLock(
            LeasedContext(reader), callback);
      } finally {
        reader.returnLease();
      }
    });
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    final pool = await _pool;
    return _runInLockContext(() async {
      final reader = await pool.writer(abortSignal: lockTimeout?.asTimeout);
      try {
        return await ScopedWriteContext.assumeWriteLock(
            LeasedContext(reader), callback);
      } finally {
        reader.returnLease();
      }
    });
  }

  @override
  Future<void> refreshSchema() async {
    _checkNotLocked();
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
    return _runInLockContext(() async {
      final exclusiveAccess = await pool.exclusiveAccess();

      final writer = ScopedWriteContext(LeasedContext(exclusiveAccess.writer));
      final readers = [
        for (final reader in exclusiveAccess.readers)
          ScopedReadContext(LeasedContext(reader))
      ];
      try {
        return await block(writer, readers);
      } finally {
        writer.invalidate();
        for (final reader in readers) {
          reader.invalidate();
        }

        exclusiveAccess.close();
      }
    });
  }

  void _checkNotLocked() {
    if (Zone.current[_lockGuard] != null) {
      throw LockError(
          'Blocked attempt to use connection object in a read/write lock callback.');
    }
  }

  T _runInLockContext<T>(T Function() inner) {
    _checkNotLocked();
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
