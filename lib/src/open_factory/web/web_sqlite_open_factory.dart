import 'package:sqlite_async/src/sqlite_options.dart';
import 'package:sqlite3/wasm.dart';
import '../abstract_open_factory.dart';

class DefaultSqliteOpenFactory
    extends AbstractDefaultSqliteOpenFactory<CommonDatabase> {
  const DefaultSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()});

  @override
  CommonDatabase openDB(SqliteOpenOptions options) {
    if (sqliteOptions.wasmSqlite3 == null) {
      throw ArgumentError('WASM Sqlite3 implementation was not provided');
    }

    return sqliteOptions.wasmSqlite3!.open("/" + path);
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    // WAL mode is not supported on web
    return [];
  }
}
