import 'dart:async';

import 'package:collection/collection.dart';

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

  /// Throttle an UpdateNotification stream to trigger a maximum of once
  /// every [timeout].
  ///
  /// Use [addOne] to immediately send one update to the output stream.
  static Stream<UpdateNotification> throttleStream(
      Stream<UpdateNotification> input, Duration timeout,
      {UpdateNotification? addOne}) {
    return _throttleStream(
      input: input,
      timeout: timeout,
      throttleFirst: true,
      add: (a, b) => a.union(b),
      addOne: addOne,
    );
  }

  /// Filter an update stream by specific tables.
  static StreamTransformer<UpdateNotification, UpdateNotification>
      filterTablesTransformer(Iterable<String> tables) {
    Set<String> normalized = {for (var table in tables) table.toLowerCase()};
    return StreamTransformer.fromBind(
        (source) => source.where((data) => data.containsAny(normalized)));
  }
}

/// Throttles an [input] stream to not emit events more often than with a
/// frequency of 1/[timeout].
///
/// When an event is received and no timeout window is active, it is forwarded
/// downstream and a timeout window is started. For events received within a
/// timeout window, [add] is called to fold events. Then when the window
/// expires, pending events are emitted.
/// The subscription to the [input] stream is never paused.
///
/// When the returned stream is paused, an active timeout window is reset and
/// restarts after the stream is resumed.
///
/// If [addOne] is not null, that event will always be added when the stream is
/// subscribed to.
/// When [throttleFirst] is true, a timeout window begins immediately after
/// listening (so that the first event, apart from [addOne], is emitted no
/// earlier than after [timeout]).
Stream<T> _throttleStream<T extends Object>({
  required Stream<T> input,
  required Duration timeout,
  required bool throttleFirst,
  required T Function(T, T) add,
  required T? addOne,
}) {
  return Stream.multi((listener) {
    T? pendingData;
    Timer? activeTimeoutWindow;

    /// Add pending data, bypassing the active timeout window.
    ///
    /// This is used to forward error and done events immediately.
    bool addPendingEvents() {
      if (pendingData case final data?) {
        pendingData = null;
        listener.addSync(data);
        activeTimeoutWindow?.cancel();
        return true;
      } else {
        return false;
      }
    }

    /// Emits [pendingData] if no timeout window is active, and then starts a
    /// timeout window if necessary.
    void maybeEmit() {
      if (activeTimeoutWindow == null && !listener.isPaused) {
        final didAdd = addPendingEvents();
        if (didAdd) {
          activeTimeoutWindow = Timer(timeout, () {
            activeTimeoutWindow = null;
            maybeEmit();
          });
        }
      }
    }

    void setTimeout() {
      activeTimeoutWindow = Timer(timeout, () {
        activeTimeoutWindow = null;
        maybeEmit();
      });
    }

    void onData(T data) {
      pendingData = switch (pendingData) {
        null => data,
        final pending => add(pending, data),
      };
      maybeEmit();
    }

    void onError(Object error, StackTrace trace) {
      addPendingEvents();
      listener.addErrorSync(error, trace);
    }

    void onDone() {
      addPendingEvents();
      listener.closeSync();
    }

    final subscription = input.listen(onData, onError: onError, onDone: onDone);
    var needsTimeoutWindowAfterResume = false;

    listener.onPause = () {
      needsTimeoutWindowAfterResume = activeTimeoutWindow != null;
      activeTimeoutWindow?.cancel();
    };
    listener.onResume = () {
      if (needsTimeoutWindowAfterResume) {
        setTimeout();
      } else {
        maybeEmit();
      }
    };
    listener.onCancel = () async {
      activeTimeoutWindow?.cancel();
      return subscription.cancel();
    };

    if (addOne != null) {
      // This must not be sync, we're doing this directly in onListen
      listener.add(addOne);
    }
    if (throttleFirst) {
      setTimeout();
    }
  });
}
