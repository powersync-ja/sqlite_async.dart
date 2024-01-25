import 'dart:async';

import 'package:sqlite3/common.dart';
import 'package:sqlite_async/definitions.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import '../common/abstract_isolate_connection_factory.dart';

/// A connection factory that can be passed to different isolates.
class IsolateConnectionFactory extends AbstractIsolateConnectionFactory {
  AbstractDefaultSqliteOpenFactory openFactory;

  IsolateConnectionFactory({
    required this.openFactory,
  });

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
  Future<CommonDatabase> openRawDatabase({bool readOnly = false}) async {
    throw UnimplementedError();
  }
}
