import '../common/abstract_open_factory.dart';
import '../sqlite_options.dart';
import '../web/database/web_sqlite_database.dart';
import '../web/web_sqlite_open_factory.dart';

WebSqliteOpenFactory createDefaultOpenFactory(
    String path, SqliteOptions options) {
  return WebSqliteOpenFactory(path: path, sqliteOptions: options);
}

AsyncWebDatabaseImpl openDatabaseWithFactory(SqliteOpenFactory factory) {
  // It's safe to cast here, SqliteOpenFactory can only be implemented by
  // WebSqliteOpenFactory when compiling to the web (the class is sealed).
  return AsyncWebDatabaseImpl(factory as WebSqliteOpenFactory);
}
