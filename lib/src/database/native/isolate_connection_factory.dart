import 'dart:async';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../mutex.dart';
import '../../sqlite_connection.dart';
import '../../sqlite_open_factory.dart';
import '../../update_notification.dart';
import '../../utils/native_database_utils.dart';
import 'port_channel.dart';
import 'sqlite_connection_impl.dart';

/// A connection factory that can be passed to different isolates.
class IsolateConnectionFactory {
  SqliteOpenFactory<sqlite.Database> openFactory;
  SerializedMutex mutex;
  SerializedPortClient upstreamPort;

  IsolateConnectionFactory(
      {required this.openFactory,
      required this.mutex,
      required this.upstreamPort});

  /// Open a new SqliteConnection.
  ///
  /// This opens a single connection in a background execution isolate.
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

  /// Opens a synchronous sqlite.Database directly in the current isolate.
  ///
  /// This gives direct access to the database, but:
  ///  1. No app-level locking is performed automatically. Transactions may fail
  ///     with SQLITE_BUSY if another isolate is using the database at the same time.
  ///  2. Other connections are not notified of any updates to tables made within
  ///     this connection.
  Future<sqlite.Database> openRawDatabase({bool readOnly = false}) async {
    final db = await openFactory
        .open(SqliteOpenOptions(primaryConnection: false, readOnly: readOnly));
    return db;
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
