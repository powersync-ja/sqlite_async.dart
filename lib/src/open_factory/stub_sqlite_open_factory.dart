import 'package:sqlite3/common.dart';
import 'package:sqlite_async/src/sqlite_open_factory.dart';
import 'package:sqlite_async/src/sqlite_options.dart';

class DefaultSqliteOpenFactory extends AbstractDefaultSqliteOpenFactory {
  const DefaultSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()});

  @override
  CommonDatabase openDB(SqliteOpenOptions options) {
    throw UnimplementedError();
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    throw UnimplementedError();
  }
}
