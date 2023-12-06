import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite_async/src/sqlite_open_factory.dart';
import 'package:sqlite_async/src/sqlite_options.dart';

class DefaultSqliteOpenFactory
    extends AbstractDefaultSqliteOpenFactory<Database> {
  const DefaultSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()});

  @override
  Database open(SqliteOpenOptions options) {
    final mode = options.openMode;
    var db = sqlite3.open(path, mode: mode, mutex: false);

    for (var statement in pragmaStatements(options)) {
      db.execute(statement);
    }
    return db;
  }
}
