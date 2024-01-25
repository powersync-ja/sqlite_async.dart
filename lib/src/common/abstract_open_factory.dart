import 'dart:async';
import 'package:meta/meta.dart';

import 'package:sqlite_async/sqlite3_common.dart' as sqlite;
import 'package:sqlite_async/src/sqlite_options.dart';

/// Factory to create new SQLite database connections.
///
/// Since connections are opened in dedicated background isolates, this class
/// must be safe to pass to different isolates.
abstract class SqliteOpenFactory<Database extends sqlite.CommonDatabase> {
  String get path;

  FutureOr<Database> open(SqliteOpenOptions options);
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

/// The default database factory.
///
/// This takes care of opening the database, and running PRAGMA statements
/// to configure the connection.
///
/// Override the [open] method to customize the process.
abstract class AbstractDefaultSqliteOpenFactory<
        Database extends sqlite.CommonDatabase>
    implements SqliteOpenFactory<Database> {
  final String path;
  final SqliteOptions sqliteOptions;

  const AbstractDefaultSqliteOpenFactory(
      {required this.path,
      this.sqliteOptions = const SqliteOptions.defaults()});

  List<String> pragmaStatements(SqliteOpenOptions options);

  @protected
  FutureOr<Database> openDB(SqliteOpenOptions options);

  @override
  FutureOr<Database> open(SqliteOpenOptions options) async {
    var db = await openDB(options);

    for (var statement in pragmaStatements(options)) {
      db.execute(statement);
    }
    return db;
  }
}
