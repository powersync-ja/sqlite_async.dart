import 'dart:async';

import 'package:sqlite3/common.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_open_factory.dart';
import 'package:sqlite_async/src/sqlite_options.dart';

class DefaultSqliteOpenFactoryImplementation
    extends AbstractDefaultSqliteOpenFactory {
  const DefaultSqliteOpenFactoryImplementation(
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

  @override
  FutureOr<SQLExecutor> openExecutor(SqliteOpenOptions options) {
    throw UnimplementedError();
  }
}
