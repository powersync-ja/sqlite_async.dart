import 'package:sqlite_async/sqlite_async.dart';

class TestDefaultSqliteOpenFactory extends DefaultSqliteOpenFactory {
  final String sqlitePath;

  TestDefaultSqliteOpenFactory(
      {required super.path, super.sqliteOptions, this.sqlitePath = ''});
}

abstract class AbstractTestUtils {
  String dbPath();

  /// Generates a test open factory
  Future<TestDefaultSqliteOpenFactory> testFactory(
      {String? path,
      String sqlitePath = '',
      List<String> initStatements = const [],
      SqliteOptions options = const SqliteOptions.defaults()}) async {
    return TestDefaultSqliteOpenFactory(
      path: path ?? dbPath(),
      sqliteOptions: options,
    );
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
