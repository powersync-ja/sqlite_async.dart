import 'dart:async';
import 'package:sqlite_async/mutex.dart';
import 'package:sqlite_async/sqlite3_common.dart' as sqlite;
import 'package:sqlite_async/src/sqlite_connection.dart';

import 'abstract_open_factory.dart';
import 'port_channel.dart';

/// A connection factory that can be passed to different isolates.
abstract class AbstractIsolateConnectionFactory<
    Database extends sqlite.CommonDatabase> {
  AbstractDefaultSqliteOpenFactory<Database> get openFactory;

  AbstractMutex get mutex;

  SerializedPortClient get upstreamPort;

  /// Open a new SqliteConnection.
  ///
  /// This opens a single connection in a background execution isolate.
  SqliteConnection open({String? debugName, bool readOnly = false});

  /// Opens a synchronous sqlite.Database directly in the current isolate.
  ///
  /// This gives direct access to the database, but:
  ///  1. No app-level locking is performed automatically. Transactions may fail
  ///     with SQLITE_BUSY if another isolate is using the database at the same time.
  ///  2. Other connections are not notified of any updates to tables made within
  ///     this connection.
  FutureOr<Database> openRawDatabase({bool readOnly = false}) async {
    return openFactory
        .open(SqliteOpenOptions(primaryConnection: false, readOnly: readOnly));
  }
}
