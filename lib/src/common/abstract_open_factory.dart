import 'dart:async';
import 'package:meta/meta.dart';

import 'package:sqlite_async/sqlite3_common.dart' as sqlite;
import 'package:sqlite_async/src/common/mutex.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_options.dart';
import 'package:sqlite_async/src/update_notification.dart';

/// Factory to create new SQLite database connections.
///
/// Since connections are opened in dedicated background isolates, this class
/// must be safe to pass to different isolates.
abstract class SqliteOpenFactory<Database extends sqlite.CommonDatabase> {
  String get path;

  /// Opens a direct connection to the SQLite database
  Database open(SqliteOpenOptions options);

  /// Opens an asynchronous [SqliteConnection]
  FutureOr<SqliteConnection> openConnection(SqliteOpenOptions options);
}

class SqliteOpenOptions {
  /// Whether this is the primary write connection for the database.
  final bool primaryConnection;

  /// Whether this connection is read-only.
  final bool readOnly;

  /// Mutex to use in [SqliteConnection]s
  final Mutex? mutex;

  /// Name used in debug logs
  final String? debugName;

  /// Stream of external update notifications
  final Stream<UpdateNotification>? updates;

  const SqliteOpenOptions(
      {required this.primaryConnection,
      required this.readOnly,
      this.mutex,
      this.debugName,
      this.updates});

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
  @override
  final String path;
  final SqliteOptions sqliteOptions;

  const AbstractDefaultSqliteOpenFactory(
      {required this.path,
      this.sqliteOptions = const SqliteOptions.defaults()});

  List<String> pragmaStatements(SqliteOpenOptions options);

  @protected

  /// Opens a direct connection to a SQLite database connection
  Database openDB(SqliteOpenOptions options);

  @override

  /// Opens a direct connection to a SQLite database connection
  /// and executes setup pragma statements to initialize the DB
  Database open(SqliteOpenOptions options) {
    var db = openDB(options);

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

  @override

  /// Opens an asynchronous [SqliteConnection] to a SQLite database
  /// and executes setup pragma statements to initialize the DB
  FutureOr<SqliteConnection> openConnection(SqliteOpenOptions options);
}
