import 'dart:async';

import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/src/common/isolate_connection_factory.dart';
import 'package:sqlite_async/src/common/mutex.dart';
import 'package:sqlite_async/src/common/port_channel.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/web/web_sqlite_open_factory.dart';

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
      required SerializedPortClient upstreamPort});

  /// Not supported on web
  @override
  SqliteConnection open({String? debugName, bool readOnly = false}) {
    throw UnimplementedError();
  }

  /// Not supported on web
  @override
  Future<CommonDatabase> openRawDatabase({bool readOnly = false}) async {
    throw UnimplementedError();
  }

  @override
  SerializedPortClient get upstreamPort => throw UnimplementedError();
}
