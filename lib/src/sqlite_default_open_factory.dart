import './sqlite_open_factory.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:sqlite3/common.dart' as sqlite_common;
import 'sqlite_options.dart';

/// The default database factory.
///
/// This takes care of opening the database, and running PRAGMA statements
/// to configure the connection.
///
/// Override the [open] method to customize the process.
class DefaultSqliteOpenFactory implements SqliteOpenFactory {
  final String path;
  final SqliteOptions sqliteOptions;

  const DefaultSqliteOpenFactory(
      {required this.path,
      this.sqliteOptions = const SqliteOptions.defaults()});

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
  sqlite_common.CommonDatabase open(SqliteOpenOptions options) {
    final mode = options.openMode;
    var db = sqlite.sqlite3.open(path, mode: mode, mutex: false);

    for (var statement in pragmaStatements(options)) {
      db.execute(statement);
    }
    return db;
  }
}
