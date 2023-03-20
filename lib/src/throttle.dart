import 'dart:async';

import 'update_notification.dart';

StreamTransformer<T, T> throttleTransformer<T>(Duration timeout) {
  Timer? timer;
  T? lastData;

  return StreamTransformer<T, T>.fromHandlers(handleData: (data, sink) {
    lastData = data;
    timer ??= Timer(timeout, () {
      sink.add(lastData as T);
      timer = null;
      lastData = null;
    });
  });
}

/// Given a broadcast stream, return a singular throttled stream that is throttled.
/// This immediately starts listening.
///
/// Behaviour:
///   If there was no event in "timeout", and one comes in, it is pushed immediately.
///   Otherwise, we wait until the timeout is over.
Stream<T> throttleStream<T>(Stream<T> input, Duration timeout,
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

Stream<UpdateNotification> throttleUpdateNotifications(
    Stream<UpdateNotification> input, Duration timeout,
    {UpdateNotification? addOne}) {
  return throttleStream(input, timeout, addOne: addOne, throttleFirst: true,
      add: (a, b) {
    return UpdateNotification(a.tables.union(b.tables));
  });
}

/// Filter an update stream by specific tables
StreamTransformer<UpdateNotification, UpdateNotification>
    filterTablesTransformer(Iterable<String> tables) {
  Set<String> normalized = {for (var table in tables) table.toLowerCase()};
  return StreamTransformer<UpdateNotification, UpdateNotification>.fromHandlers(
      handleData: (data, sink) {
    if (data.containsAny(normalized)) {
      sink.add(data);
    }
  });
}
