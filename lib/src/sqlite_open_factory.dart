export './open_factory/abstract_open_factory.dart';

import 'dart:async';

import 'package:sqlite3/common.dart';
import 'package:sqlite_async/definitions.dart';

import './open_factory/open_factory_adapter.dart' as base;

class DefaultSqliteOpenFactory<T extends CommonDatabase>
    extends AbstractDefaultSqliteOpenFactory<T> {
  late AbstractDefaultSqliteOpenFactory<T> adapter;

  DefaultSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()}) {
    adapter = base.DefaultSqliteOpenFactory(
            path: path, sqliteOptions: super.sqliteOptions)
        as AbstractDefaultSqliteOpenFactory<T>;
  }

  @override
  FutureOr<T> openDB(SqliteOpenOptions options) {
    return adapter.openDB(options);
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    return adapter.pragmaStatements(options);
  }

  @override
  FutureOr<SQLExecutor> openWeb(SqliteOpenOptions options) {
    return adapter.openWeb(options);
  }
}
