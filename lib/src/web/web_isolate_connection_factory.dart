import 'dart:async';

import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/common/isolate_connection_factory.dart';
import 'package:sqlite_async/src/common/mutex.dart';
import 'package:sqlite_async/src/common/port_channel.dart';
import 'package:sqlite_async/src/web/web_sqlite_open_factory.dart';
import 'database/web_sqlite_connection_impl.dart';

/// An implementation of [IsolateConnectionFactory] for Web
/// This uses a web worker instead of an isolate
class IsolateConnectionFactoryImpl
    with IsolateOpenFactoryMixin
    implements IsolateConnectionFactory {
  @override
  DefaultSqliteOpenFactory openFactory;

  @override
  Mutex mutex;

  IsolateConnectionFactoryImpl(
      {required this.openFactory,
      required this.mutex,
      SerializedPortClient? upstreamPort});

  /// Open a new SqliteConnection.
  ///
  /// This opens a single connection in a background execution isolate.
  @override
  WebSqliteConnectionImpl open({String? debugName, bool readOnly = false}) {
    return WebSqliteConnectionImpl(mutex: mutex, openFactory: openFactory);
  }

  /// Opens a synchronous sqlite.Database directly in the current isolate.
  /// This should not be used in conjunction with async connections provided
  /// by Drift.
  ///
  /// This gives direct access to the database, but:
  ///  1. No app-level locking is performed automatically. Transactions may fail
  ///     with SQLITE_BUSY if another isolate is using the database at the same time.
  ///  2. Other connections are not notified of any updates to tables made within
  ///     this connection.
  @override
  Future<CommonDatabase> openRawDatabase({bool readOnly = false}) async {
    return openFactory
        .open(SqliteOpenOptions(primaryConnection: false, readOnly: readOnly));
  }

  @override
  SerializedPortClient get upstreamPort => throw UnimplementedError();
}
