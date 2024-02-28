import 'dart:async';
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:sqlite_async/src/common/isolate_connection_factory.dart';
import 'package:sqlite_async/src/common/port_channel.dart';
import 'package:sqlite_async/src/native/native_isolate_mutex.dart';
import 'package:sqlite_async/src/native/native_sqlite_open_factory.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:sqlite_async/src/utils/database_utils.dart';
import 'database/native_sqlite_connection_impl.dart';

mixin UpStreamTableUpdates {
  final StreamController<UpdateNotification> updatesController =
      StreamController.broadcast();

  late SerializedPortClient upstreamPort;

  @protected

  /// Resolves once the primary connection is initialized
  late Future<void> isInitialized;

  @protected
  PortServer? eventsPort;

  @protected
  SerializedPortClient listenForEvents() {
    UpdateNotification? updates;

    Map<SendPort, StreamSubscription> subscriptions = {};

    eventsPort = PortServer((message) async {
      if (message is UpdateNotification) {
        if (updates == null) {
          updates = message;
          // Use the mutex to only send updates after the current transaction.
          // Do take care to avoid getting a lock for each individual update -
          // that could add massive performance overhead.
          if (updates != null) {
            updatesController.add(updates!);
            updates = null;
          }
        } else {
          updates!.tables.addAll(message.tables);
        }
        return null;
      } else if (message is InitDb) {
        await isInitialized;
        return null;
      } else if (message is SubscribeToUpdates) {
        if (subscriptions.containsKey(message.port)) {
          return;
        }
        final subscription = updatesController.stream.listen((event) {
          message.port.send(event);
        });
        subscriptions[message.port] = subscription;
        return null;
      } else if (message is UnsubscribeToUpdates) {
        final subscription = subscriptions.remove(message.port);
        subscription?.cancel();
        return null;
      } else {
        throw ArgumentError('Unknown message type: $message');
      }
    });
    return upstreamPort = eventsPort!.client();
  }
}

/// A connection factory that can be passed to different isolates.
class IsolateConnectionFactoryImpl
    with IsolateOpenFactoryMixin, UpStreamTableUpdates
    implements IsolateConnectionFactory {
  @override
  DefaultSqliteOpenFactory openFactory;

  @override
  SerializedMutex mutex;

  IsolateConnectionFactoryImpl(
      {required this.openFactory,
      required this.mutex,
      SerializedPortClient? port}) {
    upstreamPort = port ?? listenForEvents();
  }

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
        port: upstreamPort,
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
      super.port,
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
