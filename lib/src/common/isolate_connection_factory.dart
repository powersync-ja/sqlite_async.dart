import 'dart:async';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/src/common/mutex.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/impl/isolate_connection_factory_impl.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'port_channel.dart';

mixin IsolateOpenFactoryMixin<Database extends CommonDatabase> {
  AbstractDefaultSqliteOpenFactory<Database> get openFactory;

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

/// A connection factory that can be passed to different isolates.
abstract class IsolateConnectionFactory<Database extends CommonDatabase>
    with IsolateOpenFactoryMixin {
  Mutex get mutex;

  SerializedPortClient get upstreamPort;

  factory IsolateConnectionFactory(
      {required openFactory,
      required mutex,
      required SerializedPortClient upstreamPort}) {
    return IsolateConnectionFactoryImpl(
        openFactory: openFactory,
        mutex: mutex,
        upstreamPort: upstreamPort) as IsolateConnectionFactory<Database>;
  }

  /// Open a new SqliteConnection.
  ///
  /// This opens a single connection in a background execution isolate.
  SqliteConnection open({String? debugName, bool readOnly = false});
}
