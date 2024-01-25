// This follows the pattern from here: https://stackoverflow.com/questions/58710226/how-to-import-platform-specific-dependency-in-flutter-dart-combine-web-with-an
// To conditionally export an implementation for either web or "native" platforms
// The sqlite library uses dart:ffi which is not supported on web
import 'package:sqlite_async/sqlite_async.dart';
export 'package:sqlite_async/src/database/abstract_sqlite_database.dart';
import 'database/sqlite_database_impl.dart';

class SqliteDatabase extends AbstractSqliteDatabase {
  static const int defaultMaxReaders = AbstractSqliteDatabase.defaultMaxReaders;

  late AbstractSqliteDatabase adapter;

  @override
  int get maxReaders {
    return adapter.maxReaders;
  }

  @override
  Future<void> get isInitialized {
    return adapter.isInitialized;
  }

  @override
  SqliteOpenFactory get openFactory {
    return adapter.openFactory;
  }

  /// Use this stream to subscribe to notifications of updates to tables.
  @override
  Stream<UpdateNotification> get updates {
    return adapter.updates;
  }

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
  SqliteDatabase(
      {required path,
      int maxReaders = AbstractSqliteDatabase.defaultMaxReaders,
      SqliteOptions options = const SqliteOptions.defaults()}) {
    final openFactory =
        DefaultSqliteOpenFactory(path: path, sqliteOptions: options);
    adapter = SqliteDatabaseImplementation.withFactory(openFactory,
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
  SqliteDatabase.withFactory(SqliteOpenFactory openFactory,
      {int maxReaders = AbstractSqliteDatabase.defaultMaxReaders}) {
    adapter = SqliteDatabaseImplementation.withFactory(openFactory,
        maxReaders: maxReaders);
  }

  @override
  Future<void> close() {
    return adapter.close();
  }

  @override
  bool get closed => adapter.closed;

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    return adapter.readLock(callback,
        lockTimeout: lockTimeout, debugContext: debugContext);
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    return adapter.writeLock(callback,
        lockTimeout: lockTimeout, debugContext: debugContext);
  }

  @override
  AbstractIsolateConnectionFactory isolateConnectionFactory() {
    return adapter.isolateConnectionFactory();
  }
}
