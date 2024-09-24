import 'dart:async';

import 'package:meta/meta.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/common/sqlite_database.dart';
import 'package:sqlite_async/src/native/database/connection_pool.dart';
import 'package:sqlite_async/src/native/database/native_sqlite_connection_impl.dart';
import 'package:sqlite_async/src/native/native_isolate_connection_factory.dart';
import 'package:sqlite_async/src/native/native_isolate_mutex.dart';
import 'package:sqlite_async/src/native/native_sqlite_open_factory.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_options.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
import 'package:sqlite_async/src/update_notification.dart';

/// A SQLite database instance.
///
/// Use one instance per database file. If multiple instances are used, update
/// notifications may not trigger, and calls may fail with "SQLITE_BUSY" errors.
class SqliteDatabaseImpl
    with SqliteQueries, SqliteDatabaseMixin
    implements SqliteDatabase {
  @override
  final DefaultSqliteOpenFactory openFactory;

  @override
  late Stream<UpdateNotification> updates;

  @override
  int maxReaders;

  /// Global lock to serialize write transactions.
  final SimpleMutex mutex = SimpleMutex();

  @override
  @protected
  // Native doesn't require any asynchronous initialization
  late Future<void> isInitialized = Future.value();

  late final SqliteConnectionImpl _internalConnection;
  late final SqliteConnectionPool _pool;

  @override
  int get numConnections => _pool.getNumConnections();

  final StreamController<UpdateNotification> updatesController =
      StreamController.broadcast();

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
      {required path,
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
      : openFactory = factory as DefaultSqliteOpenFactory {
    _internalConnection = _openPrimaryConnection(debugName: 'sqlite-writer');
    _pool = SqliteConnectionPool(openFactory,
        writeConnection: _internalConnection,
        debugName: 'sqlite',
        maxReaders: maxReaders,
        mutex: mutex);
    // Updates get updates from the pool
    updates = _pool.updates;
  }

  @override
  bool get closed {
    return _pool.closed;
  }

  /// Returns true if the _write_ connection is in auto-commit mode
  /// (no active transaction).
  @override
  Future<bool> getAutoCommit() {
    return _pool.getAutoCommit();
  }

  /// A connection factory that can be passed to different isolates.
  ///
  /// Use this to access the database in background isolates.
  @override
  IsolateConnectionFactoryImpl isolateConnectionFactory() {
    return IsolateConnectionFactoryImpl(
        openFactory: openFactory,
        mutex: mutex.shared,
        upstreamPort: _pool.upstreamPort!);
  }

  @override
  Future<void> close() async {
    await _pool.close();
    updatesController.close();
    await mutex.close();
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
      {Duration? lockTimeout}) {
    return _pool.readTransaction(callback, lockTimeout: lockTimeout);
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
    return _pool.writeTransaction(callback, lockTimeout: lockTimeout);
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    return _pool.readLock(callback,
        lockTimeout: lockTimeout, debugContext: debugContext);
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    return _pool.writeLock(callback,
        lockTimeout: lockTimeout, debugContext: debugContext);
  }

  SqliteConnectionImpl _openPrimaryConnection({String? debugName}) {
    return SqliteConnectionImpl(
        primary: true,
        debugName: debugName,
        mutex: mutex,
        readOnly: false,
        openFactory: openFactory);
  }

  @override
  Future<void> refreshSchema() {
    return _pool.refreshSchema();
  }

  @override
  int getNumConnections() {
    return -1;
  }

  @override
  List<SqliteConnection> getAllConnections() {
    return _pool.getAllConnections();
  }
}
