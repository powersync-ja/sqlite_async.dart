import 'dart:async';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Notification of an update to one or more tables, for the purpose of realtime change
/// notifications.
class UpdateNotification {
  /// Table name
  final Set<String> tables;

  const UpdateNotification(this.tables);

  const UpdateNotification.empty() : tables = const {};
  UpdateNotification.single(String table) : tables = {table};

  @override
  bool operator ==(Object other) {
    return other is UpdateNotification &&
        const SetEquality<String>().equals(other.tables, tables);
  }

  @override
  int get hashCode {
    return Object.hashAllUnordered(tables);
  }

  @override
  String toString() {
    return "UpdateNotification<$tables>";
  }

  UpdateNotification union(UpdateNotification other) {
    return UpdateNotification(tables.union(other.tables));
  }

  /// True if any of the supplied tables have been modified.
  ///
  /// Important: Use lower case for each table in [tableFilter].
  bool containsAny(Set<String> tableFilter) {
    for (var table in tables) {
      if (tableFilter.contains(table.toLowerCase())) {
        return true;
      }
    }
    return false;
  }
}

extension ThrottleUpdateNotifications on Stream<UpdateNotification> {
  /// Turns a (likely broadcast) stream of [UpdateNotification]s into a single-
  /// subscription stream with support for backpressure by accumulating update
  /// notifications.
  ///
  /// If the listener is paused while an update notification is received on this
  /// stream, we merge it into a growing set of updates that is emitted once the
  /// listener unpauses.
  Stream<UpdateNotification> get accumulated =>
      filterAndAccumulate((_) => true);

  /// Returns a backpressure-aware stream of filtered update notifications.
  ///
  /// Each emitted event will only contain tables matched by [tableFilter].
  ///
  /// Additionally, if this stream emits an event while the listener is paused,
  /// it will get buffered in a growing set of affected tables. Then, when the
  /// listener resumes, it will be informed about all tables updated in the
  /// meantime.
  ///
  /// Consider an example:
  ///
  ///  1. A listener attaches with a table filter matching all tables.
  ///  2. We receive a table update on table `a`, which is forwarded to the
  ///     listener.
  ///  3. The listener pauses.
  ///  4. We receive another table update on `a`.
  ///  5. We receive a table update on `b`.
  ///  6. We receive yet another table update on `a`.
  ///  7. The listener resumes.
  ///  8. The listener receives a table update `{a, b}`.
  ///
  /// Without the accumulation middleware, the listener would receive three
  /// events in step 8 (`{a}`, `{b}`, `{a}`). For streams that just need to
  /// know whether a table was updated since the last pause, calling
  /// [filterAndAccumulate] thus makes listening to table updates more
  /// efficient.
  Stream<UpdateNotification> filterAndAccumulate(
      bool Function(String table) tableFilter) {
    final upstream = this;

    return Stream.multi((listener) {
      Set<String>? undeliveredEvent;

      void emitPending() {
        if (undeliveredEvent case final pending?) {
          listener.add(UpdateNotification(pending));
          undeliveredEvent = null;
        }
      }

      void handleData(UpdateNotification notification) {
        final filtered = notification.tables.where(tableFilter);
        if (undeliveredEvent case final pending?) {
          pending.addAll(filtered);
        } else {
          final asSet = {...filtered};
          if (listener.isPaused) {
            undeliveredEvent = asSet;
          } else {
            // Not paused and no outstanding buffered events, we can deliver
            // this synchronously.
            listener.addSync(UpdateNotification(asSet));
          }
        }
      }

      void handleDone() {
        emitPending();
        listener.close();
      }

      final subscription = upstream.listen(handleData, onDone: handleDone);
      listener
        ..onResume = emitPending
        ..onCancel = subscription.cancel;
    });
  }

  /// Throttles this stream to not emit events more often than with a frequency
  /// of 1/[timeout].
  ///
  /// When an event is received and no timeout window is active, it is forwarded
  /// downstream and the upstream subscription is paused during that window.
  ///
  /// This should typically be installed on streams after a
  /// [filterAndAccumulate] transformer, which accumulates table updates while
  /// the downstream listener is paused to emit them as a single event.
  @internal
  Stream<UpdateNotification> throttleWithPause(Duration? throttle) {
    if (throttle == null) return this;

    return Stream.multi((listener) {
      final subscription = listen(null);
      Timer? currentTimeout;

      subscription
        ..onData((event) {
          assert(currentTimeout == null);
          // Note: There is no risk of this interfering with a listener pausing
          // the subscription too, pause() and resume() count internally.
          subscription.pause();
          currentTimeout = Timer(throttle, () {
            subscription.resume();
          });
        })
        ..onDone(listener.closeSync);

      listener
        ..onPause = subscription.pause
        ..onResume = subscription.resume
        ..onCancel = () {
          currentTimeout?.cancel();
          return subscription.cancel();
        };
    });
  }
}
