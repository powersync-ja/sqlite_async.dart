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
    return _throttleStream(input, timeout, addOne: addOne, throttleFirst: true,
        add: (a, b) {
      return a.union(b);
    });
  }

  /// Filter an update stream by specific tables.
  static StreamTransformer<UpdateNotification, UpdateNotification>
      filterTablesTransformer(Iterable<String> tables) {
    Set<String> normalized = {for (var table in tables) table.toLowerCase()};
    return StreamTransformer<UpdateNotification,
        UpdateNotification>.fromHandlers(handleData: (data, sink) {
      if (data.containsAny(normalized)) {
        sink.add(data);
      }
    });
  }
}

/// Given a broadcast stream, return a singular throttled stream that is throttled.
/// This immediately starts listening.
///
/// Behaviour:
///   If there was no event in "timeout", and one comes in, it is pushed immediately.
///   Otherwise, we wait until the timeout is over.
Stream<T> _throttleStream<T>(Stream<T> input, Duration timeout,
    {bool throttleFirst = false, T Function(T, T)? add, T? addOne}) async* {
  var nextPing = Completer<void>();
  T? lastData;

  var listener = input.listen((data) {
    if (lastData is T && add != null) {
      lastData = add(lastData as T, data);
    } else {
      lastData = data;
    }
    if (!nextPing.isCompleted) {
      nextPing.complete();
    }
  });

  try {
    if (addOne != null) {
      yield addOne;
    }
    if (throttleFirst) {
      await Future.delayed(timeout);
    }
    while (true) {
      // If a value is available now, we'll use it immediately.
      // If not, this waits for it.
      await nextPing.future;
      // Capture any new values coming in while we wait.
      nextPing = Completer<void>();
      T data = lastData as T;
      // Clear before we yield, so that we capture new changes while yielding
      lastData = null;
      yield data;
      // Wait a minimum of this duration between tasks
      await Future.delayed(timeout);
    }
  } finally {
    listener.cancel();
  }
}
