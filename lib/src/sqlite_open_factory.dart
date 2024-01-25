export './open_factory/abstract_open_factory.dart';

import 'dart:async';
import 'package:sqlite3/common.dart';
import 'package:sqlite_async/definitions.dart';

import 'open_factory/open_factory_impl.dart';

class DefaultSqliteOpenFactory extends AbstractDefaultSqliteOpenFactory {
  late AbstractDefaultSqliteOpenFactory adapter;

  DefaultSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()}) {
    adapter = DefaultSqliteOpenFactoryImplementation(
        path: path, sqliteOptions: super.sqliteOptions);
  }

  @override
  FutureOr<CommonDatabase> openDB(SqliteOpenOptions options) {
    return adapter.openDB(options);
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    return adapter.pragmaStatements(options);
  }

  @override
  FutureOr<SQLExecutor> openExecutor(SqliteOpenOptions options) {
    return adapter.openExecutor(options);
  }
}
