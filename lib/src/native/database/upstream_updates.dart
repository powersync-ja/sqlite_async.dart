import 'dart:async';
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:sqlite_async/src/common/port_channel.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:sqlite_async/src/utils/native_database_utils.dart';
import 'package:sqlite_async/src/utils/shared_utils.dart';

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
