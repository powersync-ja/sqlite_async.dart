import 'dart:async';
import 'dart:isolate';

import 'database_utils.dart';
import 'mutex.dart';
import 'port_channel.dart';
import 'sqlite_connection.dart';
import 'sqlite_connection_impl.dart';
import 'sqlite_open_factory.dart';
import 'update_notification.dart';

class IsolateConnectionFactory {
  SqliteOpenFactory openFactory;
  SerializedMutex mutex;
  SerializedPortClient upstreamPort;

  IsolateConnectionFactory(
      {required this.openFactory,
      required this.mutex,
      required this.upstreamPort});

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
      required super.upstreamPort,
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
