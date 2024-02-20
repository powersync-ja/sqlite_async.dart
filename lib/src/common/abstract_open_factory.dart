import 'dart:async';
import 'package:meta/meta.dart';

import 'package:sqlite_async/sqlite3_common.dart' as sqlite;
import 'package:sqlite_async/src/common/mutex.dart';
import 'package:sqlite_async/src/common/port_channel.dart';
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
  FutureOr<Database> open(SqliteOpenOptions options);

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

  final SerializedPortClient? upstreamPort;

  /// Stream of external update notifications
  final Stream<UpdateNotification>? updates;

  const SqliteOpenOptions(
      {required this.primaryConnection,
      required this.readOnly,
      this.mutex,
      this.debugName,
      this.updates,
      this.upstreamPort});

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
  FutureOr<Database> openDB(SqliteOpenOptions options);

  @override

  /// Opens a direct connection to a SQLite database connection
  /// and executes setup pragma statements to initialize the DB
  FutureOr<Database> open(SqliteOpenOptions options) async {
    var db = await openDB(options);

    for (var statement in pragmaStatements(options)) {
      db.execute(statement);
    }
    return db;
  }

  @override

  /// Opens an asynchronous [SqliteConnection] to a SQLite database
  /// and executes setup pragma statements to initialize the DB
  FutureOr<SqliteConnection> openConnection(SqliteOpenOptions options);
}
