import 'dart:async';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:mutex/mutex.dart' as mutex;
import 'dart:js_interop';
import 'dart:js_util' as js_util;
// This allows for checking things like hasProperty without the need for depending on the `js` package
import 'dart:js_interop_unsafe';
import 'package:web/web.dart';

import 'package:sqlite_async/src/common/mutex.dart';

@JS('navigator')
external Navigator get _navigator;

/// Web implementation of [Mutex]
class MutexImpl implements Mutex {
  late final mutex.Mutex fallback;
  String? identifier;
  final String resolvedIdentifier;

  MutexImpl({this.identifier})

      /// On web a lock name is required for Navigator locks.
      /// Having exclusive Mutex instances requires a somewhat unique lock name.
      /// This provides a best effort unique identifier, if no identifier is provided.
      /// This should be fine for most use cases:
      ///    - The uuid package could be added for better uniqueness if required.
      ///      This would add another package dependency to `sqlite_async` which is potentially unnecessary at this point.
      /// An identifier should be supplied for better exclusion.
      : resolvedIdentifier = identifier ??
            "${DateTime.now().microsecondsSinceEpoch}-${Random().nextDouble()}" {
    fallback = mutex.Mutex();
  }

  @override
  Future<void> close() async {
    // This isn't relevant for web at the moment.
  }

  @override
  Future<T> lock<T>(Future<T> Function() callback, {Duration? timeout}) {
    if ((_navigator as JSObject).hasProperty('locks'.toJS).toDart) {
      return _webLock(callback, timeout: timeout);
    } else {
      return _fallbackLock(callback, timeout: timeout);
    }
  }

  /// Locks the callback with a standard Mutex from the `mutex` package
  Future<T> _fallbackLock<T>(Future<T> Function() callback,
      {Duration? timeout}) {
    final completer = Completer<T>();
    // Need to implement timeout manually for this
    bool isTimedOut = false;
    Timer? timer;
    if (timeout != null) {
      timer = Timer(timeout, () {
        isTimedOut = true;
        completer
            .completeError(TimeoutException('Failed to acquire lock', timeout));
      });
    }

    fallback.protect(() async {
      try {
        if (isTimedOut) {
          // Don't actually run logic
          return;
        }
        timer?.cancel();
        final result = await callback();
        completer.complete(result);
      } catch (ex) {
        completer.completeError(ex);
      }
    });

    return completer.future;
  }

  /// Locks the callback with web Navigator locks
  Future<T> _webLock<T>(Future<T> Function() callback,
      {Duration? timeout}) async {
    final lock = await _getWebLock(timeout);
    try {
      final result = await callback();
      return result;
    } finally {
      lock.release();
    }
  }

  /// Passing the Dart callback directly to the JS Navigator can cause some weird
  /// context related bugs. Instead the JS lock callback will return a hold on the lock
  /// which is represented as a [HeldLock]. This hold can be used when wrapping the Dart
  /// callback to manage the JS lock.
  /// This is inspired and adapted from https://github.com/simolus3/sqlite3.dart/blob/7bdca77afd7be7159dbef70fd1ac5aa4996211a9/sqlite3_web/lib/src/locks.dart#L6
  Future<HeldLock> _getWebLock(Duration? timeout) {
    final gotLock = Completer<HeldLock>.sync();
    // Navigator locks can be timed out by using an AbortSignal
    final controller = AbortController();

    Timer? timer;

    if (timeout != null) {
      timer = Timer(timeout, () {
        gotLock
            .completeError(TimeoutException('Failed to acquire lock', timeout));
        controller.abort('Timeout'.toJS);
      });
    }

    // If timeout occurred before the lock is available, then this callback should not be called.
    JSPromise jsCallback(JSAny lock) {
      timer?.cancel();

      // Give the Held lock something to mark this Navigator lock as completed
      final jsCompleter = Completer.sync();
      gotLock.complete(HeldLock._(jsCompleter));
      return jsCompleter.future.toJS;
    }

    final lockOptions = JSObject();
    lockOptions['signal'] = controller.signal;
    final promise = _navigator.locks
        .request(resolvedIdentifier, lockOptions, jsCallback.toJS);
    // A timeout abort will throw an exception which needs to be handled.
    // There should not be any other unhandled lock errors.
    js_util.promiseToFuture(promise).catchError((error) {});
    return gotLock.future;
  }

  @override
  Mutex open() {
    return this;
  }
}

/// This represents a hold on an active Navigator lock.
/// This is created inside the Navigator lock callback function and is used to release the lock
/// from an external source.
@internal
class HeldLock {
  final Completer<void> _completer;

  HeldLock._(this._completer);

  void release() => _completer.complete();
}
