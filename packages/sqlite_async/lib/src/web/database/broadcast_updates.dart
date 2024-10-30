import 'dart:js_interop';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:web/web.dart' as web;

/// Utility to share received [UpdateNotification]s with other tabs using
/// broadcast channels.
class BroadcastUpdates {
  final web.BroadcastChannel _channel;

  BroadcastUpdates._(this._channel);

  BroadcastUpdates(String name)
      : _channel = web.BroadcastChannel('sqlite3_async_updates/$name');

  Stream<UpdateNotification> get updates {
    return web.EventStreamProviders.messageEvent
        .forTarget(_channel)
        .map((event) {
          final data = event.data as _BroadcastMessage;
          if (data.a == 0) {
            final payload = data.b as JSArray<JSString>;
            return UpdateNotification(
                payload.toDart.map((e) => e.toDart).toSet());
          } else {
            return null;
          }
        })
        .where((e) => e != null)
        .cast();
  }

  void send(UpdateNotification notification) {
    _channel.postMessage(_BroadcastMessage.notifications(notification));
  }
}

@JS()
@anonymous
extension type _BroadcastMessage._(JSObject _) implements JSObject {
  external int get a;
  external JSAny get b;

  external factory _BroadcastMessage({required int a, required JSAny b});

  factory _BroadcastMessage.notifications(UpdateNotification notification) {
    return _BroadcastMessage(
      a: 0,
      b: notification.tables.map((e) => e.toJS).toList().toJS,
    );
  }
}
