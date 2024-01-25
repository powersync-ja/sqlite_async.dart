import 'dart:async';

import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/src/database/web/web_sqlite_connection_impl.dart';
import 'package:sqlite_async/src/isolate_connection_factory/abstract_isolate_connection_factory.dart';
import 'package:sqlite_async/src/open_factory/web/web_sqlite_open_factory_impl.dart';
import 'package:sqlite_async/src/sqlite_open_factory.dart';
import 'package:mutex/mutex.dart';

/// A connection factory that can be passed to different isolates.
class IsolateConnectionFactory extends AbstractIsolateConnectionFactory {
  @override
  DefaultSqliteOpenFactoryImplementation openFactory;

  Mutex mutex;

  IsolateConnectionFactory({required this.openFactory, required this.mutex});

  /// Open a new SqliteConnection.
  ///
  /// This opens a single connection in a background execution isolate.
  WebSqliteConnectionImpl open({String? debugName, bool readOnly = false}) {
    return WebSqliteConnectionImpl(mutex: mutex, openFactory: openFactory);
  }

  /// Opens a synchronous sqlite.Database directly in the current isolate.
  ///
  /// This gives direct access to the database, but:
  ///  1. No app-level locking is performed automatically. Transactions may fail
  ///     with SQLITE_BUSY if another isolate is using the database at the same time.
  ///  2. Other connections are not notified of any updates to tables made within
  ///     this connection.
  Future<CommonDatabase> openRawDatabase({bool readOnly = false}) async {
    return openFactory
        .open(SqliteOpenOptions(primaryConnection: false, readOnly: readOnly));
  }
}
