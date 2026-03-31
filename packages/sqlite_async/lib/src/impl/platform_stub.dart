import '../common/abstract_open_factory.dart';
import '../common/sqlite_database.dart';
import '../sqlite_options.dart';

SqliteOpenFactory createDefaultOpenFactory(String path, SqliteOptions options) {
  throw UnsupportedError('Unsupported platform for sqlite_async package.');
}

SqliteDatabase openDatabaseWithFactory(SqliteOpenFactory factory) {
  throw UnsupportedError('Unsupported platform for sqlite_async package.');
}
