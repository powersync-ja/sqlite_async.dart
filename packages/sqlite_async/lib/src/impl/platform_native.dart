import '../common/abstract_open_factory.dart';
import '../native/database/native_sqlite_database.dart';
import '../native/native_sqlite_open_factory.dart';
import '../sqlite_options.dart';

NativeSqliteOpenFactory createDefaultOpenFactory(
    String path, SqliteOptions options) {
  return NativeSqliteOpenFactory(path: path, sqliteOptions: options);
}

NativeSqliteDatabaseImpl openDatabaseWithFactory(SqliteOpenFactory factory) {
  // It's safe to cast here, SqliteOpenFactory can only be implemented by
  // NativeSqliteOpenFactory on native platforms (the class is sealed).
  return NativeSqliteDatabaseImpl(factory as NativeSqliteOpenFactory);
}
