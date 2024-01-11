import 'package:sqlite3/common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';

import '../abstract_sqlite_database.dart';

class SqliteDatabase extends AbstractSqliteDatabase {
  @override
  bool get closed => throw UnimplementedError();

  // late final CommonDatabase con;

  // late final Future<void> _initialized;

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
  factory SqliteDatabase(
      {required path,
      int maxReaders = AbstractSqliteDatabase.defaultMaxReaders,
      SqliteOptions options = const SqliteOptions.defaults()}) {
    final factory =
        DefaultSqliteOpenFactory(path: path, sqliteOptions: options);
    return SqliteDatabase.withFactory(factory, maxReaders: maxReaders);
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
  SqliteDatabase.withFactory(SqliteOpenFactory openFactory,
      {int maxReaders = AbstractSqliteDatabase.defaultMaxReaders}) {
    super.openFactory = openFactory;
    super.maxReaders = maxReaders;
    updates = updatesController.stream;
    isInitialized = _init();
    // con = openFactory.open(options)
  }

  Future<void> _init() async {}

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    throw UnimplementedError();
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    throw UnimplementedError();
  }

  @override
  Future<void> close() {
    // TODO: implement close
    throw UnimplementedError();
  }

  @override
  IsolateConnectionFactory isolateConnectionFactory() {
    // TODO: implement isolateConnectionFactory
    throw UnimplementedError();
  }
}
