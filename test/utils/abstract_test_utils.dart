import 'package:sqlite_async/sqlite_async.dart';
import 'package:test_api/src/backend/invoker.dart';

class TestDefaultSqliteOpenFactory extends DefaultSqliteOpenFactory {
  final String sqlitePath;

  TestDefaultSqliteOpenFactory(
      {required super.path, super.sqliteOptions, this.sqlitePath = ''});
}

abstract class AbstractTestUtils {
  String dbPath() {
    final test = Invoker.current!.liveTest;
    var testName = test.test.name;
    var testShortName =
        testName.replaceAll(RegExp(r'[\s\./]'), '_').toLowerCase();
    var dbName = "test-db/$testShortName.db";
    return dbName;
  }

  /// Generates a test open factory
  Future<TestDefaultSqliteOpenFactory> testFactory(
      {String? path,
      String sqlitePath = '',
      SqliteOptions options = const SqliteOptions.defaults()}) async {
    return TestDefaultSqliteOpenFactory(
        path: path ?? dbPath(), sqliteOptions: options);
  }

  /// Creates a SqliteDatabaseConnection
  Future<SqliteDatabase> setupDatabase(
      {String? path,
      List<String> initStatements = const [],
      int maxReaders = SqliteDatabase.defaultMaxReaders}) async {
    final db = SqliteDatabase.withFactory(await testFactory(path: path),
        maxReaders: maxReaders);
    await db.initialize();
    return db;
  }

  /// Deletes any DB data
  Future<void> cleanDb({required String path});

  List<String> findSqliteLibraries();
}
