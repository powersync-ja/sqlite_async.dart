import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../common/abstract_open_factory.dart';

/// [SqliteOpenFactory] implementation for native platforms.
///
/// This class can be extended to customize how databases are opened on native
/// platforms.
base class NativeSqliteOpenFactory extends InternalOpenFactory {
  NativeSqliteOpenFactory({required super.path, super.sqliteOptions});

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    List<String> statements = [];

    if (sqliteOptions.lockTimeout != null) {
      // May be replaced by a Dart-level retry mechanism in the future
      statements.add(
          'PRAGMA busy_timeout = ${sqliteOptions.lockTimeout!.inMilliseconds}');
    }

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

  /// Opens a new native [Database] connection and runs pragma statements via
  /// [configureConnection].
  sqlite.Database openNativeConnection(SqliteOpenOptions options) {
    final mode = options.openMode;
    final db = sqlite.sqlite3.open(path, mode: mode, mutex: false);

    try {
      configureConnection(db, options);
    } on Object {
      db.close();
      rethrow;
    }
    return db;
  }

  /// Runs [pragmaStatements] for a freshly opened connection,
  void configureConnection(
      sqlite.Database database, SqliteOpenOptions options) {
    // Pragma statements don't have the same BUSY_TIMEOUT behavior as normal statements.
    // We add a manual retry loop for those.
    for (var statement in pragmaStatements(options)) {
      for (var tries = 0; tries < 30; tries++) {
        try {
          database.execute(statement);
          break;
        } on sqlite.SqliteException catch (e) {
          if (e.resultCode == sqlite.SqlError.SQLITE_BUSY && tries < 29) {
            continue;
          } else {
            rethrow;
          }
        }
      }
    }
  }
}
