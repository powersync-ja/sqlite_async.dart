import 'dart:async';
import 'package:meta/meta.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:mutex/mutex.dart';
import 'package:sqlite_async/src/database/web/web_db_context.dart';

class SqliteDatabaseImplementation extends AbstractSqliteDatabase {
  @override
  bool get closed {
    return executor == null || executor!.closed;
  }

  @override
  late Stream<UpdateNotification> updates;

  @override
  int maxReaders;

  @override
  late Future<void> isInitialized;

  @override
  SqliteOpenFactory openFactory;

  late final Future<SQLExecutor> executorFuture;
  late Mutex mutex;

  @protected
  late SQLExecutor? executor;

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
  factory SqliteDatabaseImplementation(
      {required path,
      int maxReaders = AbstractSqliteDatabase.defaultMaxReaders,
      SqliteOptions options = const SqliteOptions.defaults()}) {
    final factory =
        DefaultSqliteOpenFactory(path: path, sqliteOptions: options);
    return SqliteDatabaseImplementation.withFactory(factory,
        maxReaders: maxReaders);
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
  SqliteDatabaseImplementation.withFactory(this.openFactory,
      {this.maxReaders = AbstractSqliteDatabase.defaultMaxReaders}) {
    executorFuture = openFactory.openExecutor(
            SqliteOpenOptions(primaryConnection: true, readOnly: false))
        as Future<SQLExecutor>;
    updates = updatesController.stream;
    mutex = Mutex();
    isInitialized = _init();
  }

  Future<void> _init() async {
    executor = await executorFuture;
    executor!.updateStream.forEach((tables) {
      updatesController.add(UpdateNotification(tables));
    });
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    await isInitialized;
    return mutex.protect(() => callback(WebReadContext(executor!)));
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    await isInitialized;
    return mutex.protect(() => callback(WebWriteContext(executor!)));
  }

  @override
  Future<void> close() async {
    await isInitialized;
    await executor!.close();
  }

  @override
  IsolateConnectionFactory isolateConnectionFactory() {
    // TODO: implement isolateConnectionFactory
    throw UnimplementedError();
  }
}
