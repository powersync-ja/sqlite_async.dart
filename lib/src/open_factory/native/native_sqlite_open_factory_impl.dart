import 'dart:async';

import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite_async/src/open_factory/abstract_open_factory.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_options.dart';

class DefaultSqliteOpenFactoryImplementation
    extends AbstractDefaultSqliteOpenFactory<Database, SQLExecutor> {
  const DefaultSqliteOpenFactoryImplementation(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()});

  @override
  Database openDB(SqliteOpenOptions options) {
    final mode = options.openMode;
    var db = sqlite3.open(path, mode: mode, mutex: false);
    return db;
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    List<String> statements = [];

    if (options.primaryConnection && sqliteOptions.journalMode != null) {
      // Persisted - only needed on the primary connection
      statements
          .add('PRAGMA journal_mode = ${sqliteOptions.journalMode!.name}');
    }
    if (!options.readOnly && sqliteOptions.journalSizeLimit != null) {
      // Needed on every writable connection
      statements.add(
          'PRAGMA journal_size_limit = ${sqliteOptions.journalSizeLimit!}');
    }
    if (sqliteOptions.synchronous != null) {
      // Needed on every connection
      statements.add('PRAGMA synchronous = ${sqliteOptions.synchronous!.name}');
    }
    return statements;
  }

  @override
  FutureOr<SQLExecutor> openExecutor(SqliteOpenOptions options) {
    throw UnimplementedError();
  }
}
