export './open_factory/abstract_open_factory.dart';

import 'package:sqlite3/common.dart';
import 'package:sqlite_async/definitions.dart';

import './open_factory/stub_sqlite_open_factory.dart' as base
    if (dart.library.io) './open_factory/native/native_sqlite_open_factory.dart'
    if (dart.library.html) './open_factory/web/web_sqlite_open_factory.dart';

class DefaultSqliteOpenFactory<T extends CommonDatabase> extends AbstractDefaultSqliteOpenFactory<T> {
  late AbstractDefaultSqliteOpenFactory<T> adapter;

  DefaultSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()}) {
        adapter = base.DefaultSqliteOpenFactory(path: path, sqliteOptions: super.sqliteOptions) as AbstractDefaultSqliteOpenFactory<T>;
      }

  @override
  T openDB(SqliteOpenOptions options) {
    return adapter.openDB(options);
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    return adapter.pragmaStatements(options);
  }
}