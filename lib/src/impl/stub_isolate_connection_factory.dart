import 'dart:async';

import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/src/common/isolate_connection_factory.dart';
import 'package:sqlite_async/src/common/mutex.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/common/port_channel.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';

/// A connection factory that can be passed to different isolates.
class IsolateConnectionFactoryImpl<Database extends CommonDatabase>
    implements IsolateConnectionFactory<Database> {
  @override
  AbstractDefaultSqliteOpenFactory openFactory;

  IsolateConnectionFactoryImpl(
      {required this.openFactory,
      required Mutex mutex,
      SerializedPortClient? upstreamPort});

  @override

  /// Open a new SqliteConnection.
  ///
  /// This opens a single connection in a background execution isolate.
  SqliteConnection open({String? debugName, bool readOnly = false}) {
    throw UnimplementedError();
  }

  /// Opens a synchronous sqlite.Database directly in the current isolate.
  ///
  /// This gives direct access to the database, but:
  ///  1. No app-level locking is performed automatically. Transactions may fail
  ///     with SQLITE_BUSY if another isolate is using the database at the same time.
  ///  2. Other connections are not notified of any updates to tables made within
  ///     this connection.
  @override
  Future<Database> openRawDatabase({bool readOnly = false}) async {
    throw UnimplementedError();
  }

  @override
  Mutex get mutex => throw UnimplementedError();

  @override
  SerializedPortClient get upstreamPort => throw UnimplementedError();
}
