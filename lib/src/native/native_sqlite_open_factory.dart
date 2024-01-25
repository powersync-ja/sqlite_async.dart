import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite_async/sqlite3_common.dart';

import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/sqlite_options.dart';

class DefaultSqliteOpenFactory extends AbstractDefaultSqliteOpenFactory {
  const DefaultSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()});

  @override
  CommonDatabase openDB(SqliteOpenOptions options) {
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
}
