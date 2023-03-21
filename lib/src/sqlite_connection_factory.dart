import 'dart:async';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:sqlite_async/src/sqlite_open_factory.dart';

import 'isolate_completer.dart';
import 'mutex.dart';
import 'sqlite_connection.dart';
import 'sqlite_connection_impl.dart';
import 'update_notification.dart';

/// Advanced: Factory that can safely be serialized and sent to different isolates to
/// open connections in multiple isolates.
///
/// Not required in typical use cases.
class SqliteConnectionFactory {
  SendPort port;
  Mutex mutex;
  bool primary;

  SqliteOpenFactory openFactory;

  SqliteConnectionFactory(
      {required this.port,
      required this.mutex,
      required this.openFactory,
      this.primary = false});

  /// Open a SQLite database connection.
  /// A dedicated Isolate is spawned for running the actual queries.
  SqliteConnection openConnection(
      {String? debugName,
      Stream<UpdateNotification>? updates,
      bool readOnly = false}) {
    return SqliteConnectionImpl(this,
        debugName: debugName, updates: updates, readOnly: readOnly);
  }

  /// Open a raw sqlite.Database, providing direct access to the SQLite APIs.
  ///
  /// The APIs are low-level, and does not include automatic app-level locking.
  /// Use with care - this can easily result in DATABASE_LOCKED or other errors.
  /// All operations on this database are synchronous, and blocks the current
  /// isolate.
  Future<sqlite.Database> openRawDatabase({bool readOnly = false}) async {
    if (!primary) {
      // Wait until the primary connection has been initialized.
      // The primary connection is responsible for configuring journal mode,
      // running migrations, and other setup.
      var initialized = IsolateResult<void>();
      port.send(['init-db', initialized.completer]);
      await initialized.future;
    }
    final db = await openFactory.open(
        SqliteOpenOptions(primaryConnection: primary, readOnly: readOnly));

    return db;
  }
}
