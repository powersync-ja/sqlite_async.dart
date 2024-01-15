import 'package:sqlite_async/src/sqlite_options.dart';
import 'package:sqlite3/wasm.dart';
import '../abstract_open_factory.dart';

class DefaultSqliteOpenFactory
    extends AbstractDefaultSqliteOpenFactory<CommonDatabase> {
  // TODO only 1 connection for now
  CommonDatabase? connection;

  DefaultSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()}) {
    connection = null;
  }

  @override
  Future<CommonDatabase> openDB(SqliteOpenOptions options) async {
    if (sqliteOptions.wasmSqlite3Loader == null) {
      throw ArgumentError('WASM Sqlite3 implementation was not provided');
    }

    // TODO, only 1 connection for now
    if (connection != null) {
      return connection!;
    }

    final sqlite = await sqliteOptions.wasmSqlite3Loader!();
    return connection = sqlite.open("/" + path);
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    // WAL mode is not supported
    return [];
  }
}
