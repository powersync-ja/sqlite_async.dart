import 'dart:async';

import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
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

  @override
  FutureOr<SqliteConnection> openConnection(SqliteOpenOptions options) {
    throw UnimplementedError();
  }
}
