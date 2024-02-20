import 'dart:async';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/common/mutex.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
import 'package:sqlite_async/src/web/web_isolate_connection_factory.dart';
import 'package:sqlite_async/src/common/sqlite_database.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_options.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:sqlite_async/src/web/web_mutex.dart';
import 'package:sqlite_async/src/web/web_sqlite_open_factory.dart';

/// Web implementation of [SqliteDatabase]
/// Uses a web worker for SQLite connection
class SqliteDatabaseImpl
    with SqliteQueries, SqliteDatabaseMixin
    implements SqliteDatabase {
  @override
  bool get closed {
    return _connection.closed;
  }

  @override
  late Stream<UpdateNotification> updates;

  @override
  int maxReaders;

  @override
  late Future<void> isInitialized;

  @override
  AbstractDefaultSqliteOpenFactory openFactory;

  late final Mutex mutex;
  late final SqliteConnection _connection;

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
  SqliteDatabaseImpl.withFactory(this.openFactory,
      {this.maxReaders = SqliteDatabase.defaultMaxReaders}) {
    updates = updatesController.stream;
    mutex = MutexImpl();
    isInitialized = _init();
  }

  Future<void> _init() async {
    _connection = await openFactory.openConnection(SqliteOpenOptions(
        primaryConnection: true, readOnly: false, mutex: mutex));
    _connection.updates?.forEach((update) {
      updatesController.add(update);
    });
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    return _connection.readLock(callback,
        lockTimeout: lockTimeout, debugContext: debugContext);
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    return _connection.writeLock(callback,
        lockTimeout: lockTimeout, debugContext: debugContext);
  }

  @override
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout,
      String? debugContext}) async {
    return _connection.readTransaction(callback, lockTimeout: lockTimeout);
  }

  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout,
      String? debugContext}) async {
    return _connection.writeTransaction(callback, lockTimeout: lockTimeout);
  }

  @override
  Future<void> close() async {
    return _connection.close();
  }

  @override
  IsolateConnectionFactoryImpl isolateConnectionFactory() {
    throw UnimplementedError();
  }

  @override
  Future<bool> getAutoCommit() {
    return _connection.getAutoCommit();
  }
}
