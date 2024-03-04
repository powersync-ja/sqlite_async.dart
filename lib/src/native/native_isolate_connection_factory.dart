import 'dart:async';
import 'dart:isolate';

import 'package:sqlite_async/src/common/isolate_connection_factory.dart';
import 'package:sqlite_async/src/common/port_channel.dart';
import 'package:sqlite_async/src/native/native_isolate_mutex.dart';
import 'package:sqlite_async/src/native/native_sqlite_open_factory.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:sqlite_async/src/utils/database_utils.dart';
import 'database/native_sqlite_connection_impl.dart';

/// A connection factory that can be passed to different isolates.
class IsolateConnectionFactoryImpl
    with IsolateOpenFactoryMixin
    implements IsolateConnectionFactory {
  @override
  DefaultSqliteOpenFactory openFactory;

  @override
  SerializedMutex mutex;

  @override
  final SerializedPortClient upstreamPort;

  IsolateConnectionFactoryImpl(
      {required this.openFactory,
      required this.mutex,
      required this.upstreamPort});

  /// Open a new SqliteConnection.
  ///
  /// This opens a single connection in a background execution isolate.
  @override
  SqliteConnection open({String? debugName, bool readOnly = false}) {
    final updates = _IsolateUpdateListener(upstreamPort);

    var openMutex = mutex.open();

    return _IsolateSqliteConnection(
        openFactory: openFactory,
        mutex: openMutex,
        upstreamPort: upstreamPort,
        readOnly: readOnly,
        debugName: debugName,
        updates: updates.stream,
        closeFunction: () {
          openMutex.close();
          updates.close();
        });
  }
}

class _IsolateUpdateListener {
  final ChildPortClient client;
  final ReceivePort port = ReceivePort();
  late final StreamController<UpdateNotification> controller;

  _IsolateUpdateListener(SerializedPortClient upstreamPort)
      : client = upstreamPort.open() {
    controller = StreamController.broadcast(onListen: () {
      client.fire(SubscribeToUpdates(port.sendPort));
    }, onCancel: () {
      client.fire(UnsubscribeToUpdates(port.sendPort));
    });

    port.listen((message) {
      if (message is UpdateNotification) {
        controller.add(message);
      }
    });
  }

  Stream<UpdateNotification> get stream {
    return controller.stream;
  }

  close() {
    client.fire(UnsubscribeToUpdates(port.sendPort));
    controller.close();
    port.close();
  }
}

class _IsolateSqliteConnection extends SqliteConnectionImpl {
  final void Function() closeFunction;

  _IsolateSqliteConnection(
      {required super.openFactory,
      required super.mutex,
      super.upstreamPort,
      super.updates,
      super.debugName,
      super.readOnly = false,
      required this.closeFunction});

  @override
  Future<void> close() async {
    await super.close();
    closeFunction();
  }
}
