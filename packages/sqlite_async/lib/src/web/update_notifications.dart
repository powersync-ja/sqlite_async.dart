import 'dart:async';
import 'dart:js_interop';

import 'package:sqlite3_web/sqlite3_web.dart';

import '../update_notification.dart';
import 'protocol.dart';

/// Utility to request a stream of update notifications from the worker.
///
/// Because we want to debounce update notifications on the worker, we're using
/// custom requests instead of the default [Database.updates] stream.
///
/// Clients send a message to the worker to subscribe or unsubscribe, providing
/// an id for the subscription. The worker distributes update notifications with
/// custom requests to the client, which [handleRequest] distributes to the
/// original streams.
final class UpdateNotificationStreams {
  var _idCounter = 0;
  final Map<String, StreamController<UpdateNotification>> _updates = {};

  Future<JSAny?> handleRequest(JSAny? request) async {
    final customRequest = request as CustomDatabaseMessage;
    if (customRequest.kind == CustomDatabaseMessageKind.notifyUpdates) {
      final notification = UpdateNotification(customRequest.rawParameters.toDart
          .map((e) => (e as JSString).toDart)
          .toSet());

      final controller = _updates[customRequest.rawSql.toDart];
      controller?.add(notification);
    }

    return null;
  }

  Stream<UpdateNotification> updatesFor(Database database) {
    final id = (_idCounter++).toString();
    final controller = _updates[id] = StreamController();

    controller
      ..onListen = () {
        database.customRequest(CustomDatabaseMessage(
          CustomDatabaseMessageKind.updateSubscriptionManagement,
          id,
          [true],
        ));
      }
      ..onCancel = () {
        database.customRequest(CustomDatabaseMessage(
          CustomDatabaseMessageKind.updateSubscriptionManagement,
          id,
          [false],
        ));

        _updates.remove(id);
      };

    return controller.stream;
  }
}
