import 'dart:async';

import 'package:sqlite_async/sqlite3.dart' as sqlite;

import 'sqlite_options.dart';

/// Factory to create new SQLite database connections.
///
/// Since connections are opened in dedicated background isolates, this class
/// must be safe to pass to different isolates.
abstract class SqliteOpenFactory {
  FutureOr<sqlite.Database> open(SqliteOpenOptions options);
}

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

    if (sqliteOptions.busyTimeout != null) {
      statements.add(
          'PRAGMA busy_timeout = ${sqliteOptions.busyTimeout!.inMilliseconds}');
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

  @override
  sqlite.Database open(SqliteOpenOptions options) {
    final mode = options.openMode;
    var db = sqlite.sqlite3.open(path, mode: mode, mutex: false);

    // Pragma statements don't have the same BUSY_TIMEOUT behavior as normal statements.
    // We add a manual retry loop for those.
    for (var statement in pragmaStatements(options)) {
      for (var tries = 0; tries < 30; tries++) {
        try {
          db.execute(statement);
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
    return db;
  }
}

class SqliteOpenOptions {
  /// Whether this is the primary write connection for the database.
  final bool primaryConnection;

  /// Whether this connection is read-only.
  final bool readOnly;

  const SqliteOpenOptions(
      {required this.primaryConnection, required this.readOnly});

  sqlite.OpenMode get openMode {
    if (primaryConnection) {
      return sqlite.OpenMode.readWriteCreate;
    } else if (readOnly) {
      return sqlite.OpenMode.readOnly;
    } else {
      return sqlite.OpenMode.readWrite;
    }
  }
}
