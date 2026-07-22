import 'package:sqlite3/common.dart';
import 'package:sqlite_async/sqlite_async.dart';

abstract class AbstractTestUtils {
  String dbPath();

  Future<CommonDatabase> openDatabaseForSingleConnection();

  Future<SqliteOpenFactory> testFactory(
      {String? path, SqliteOptions options = defaultTestOptions}) async {
    return SqliteOpenFactory(path: path ?? dbPath(), options: options);
  }

  /// Creates a SqliteDatabaseConnection
  Future<SqliteDatabase> setupDatabase({
    String? path,
    SqliteOptions options = defaultTestOptions,
  }) async {
    final factory = await testFactory(path: path, options: options);
    return SqliteDatabase.withFactory(factory);
  }

  /// Deletes any DB data
  Future<void> cleanDb({required String path});

  // Enable prepared statement cache in tests, we want to enable that option by
  // default eventually.
  static const defaultTestOptions =
      SqliteOptions(preparedStatementCacheSize: 64);
}
