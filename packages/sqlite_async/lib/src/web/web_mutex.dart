import 'dart:async';
import 'dart:math';

import 'package:meta/meta.dart';
import 'dart:js_interop';
// This allows for checking things like hasProperty without the need for depending on the `js` package
import 'dart:js_interop_unsafe';
import 'package:web/web.dart';

import 'package:sqlite_async/src/common/mutex.dart';

import '../common/timeouts.dart';

@JS('navigator')
external Navigator get _navigator;

/// Web implementation of [Mutex]
class WebMutexImpl implements Mutex {
  final Mutex fallback = Mutex.simple();
  final String resolvedIdentifier;

  WebMutexImpl({String? identifier})

      /// On web a lock name is required for Navigator locks.
      /// Having exclusive Mutex instances requires a somewhat unique lock name.
      /// This provides a best effort unique identifier, if no identifier is provided.
      /// This should be fine for most use cases:
      ///    - The uuid package could be added for better uniqueness if required.
      ///      This would add another package dependency to `sqlite_async` which is potentially unnecessary at this point.
      /// An identifier should be supplied for better exclusion.
      : resolvedIdentifier = identifier ??
            "${DateTime.now().microsecondsSinceEpoch}-${Random().nextDouble()}";

  @override
  Future<T> lock<T>(Future<T> Function() callback,
      {Future<void>? abortTrigger}) {
    if (_navigator.has('locks')) {
      return _webLock(callback, abortTrigger: abortTrigger);
    } else {
      return _fallbackLock(callback, abortTrigger: abortTrigger);
    }
  }

  /// Locks the callback with a standard Mutex from the `mutex` package
  Future<T> _fallbackLock<T>(Future<T> Function() callback,
      {Future<void>? abortTrigger}) {
    return fallback.lock(callback, abortTrigger: abortTrigger);
  }

  /// Locks the callback with web Navigator locks
  Future<T> _webLock<T>(Future<T> Function() callback,
      {Future<void>? abortTrigger}) async {
    final lock = await _getWebLock(abortTrigger);
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
  Future<HeldLock> _getWebLock(Future<void>? abortTrigger) {
    final gotLock = Completer<HeldLock>.sync();
    // Navigator locks can be timed out by using an AbortSignal
    final controller = AbortController();

    if (abortTrigger != null) {
      abortTrigger.whenComplete(() {
        if (!gotLock.isCompleted) {
          gotLock.completeError(AbortException('getWebLock'));
          controller.abort('aborted in Dart'.toJS);
        }
      });
    }

    // If timeout occurred before the lock is available, then this callback should not be called.
    JSPromise jsCallback(JSAny lock) {
      // Give the Held lock something to mark this Navigator lock as completed
      final jsCompleter = Completer<void>.sync();
      if (!gotLock.isCompleted) {
        gotLock.complete(HeldLock._(jsCompleter));
      } else {
        // Already aborted, return the navigator lock asap,
        jsCompleter.complete();
      }

      return jsCompleter.future.toJS;
    }

    final lockOptions = JSObject();
    lockOptions['signal'] = controller.signal;
    final promise = _navigator.locks
        .request(resolvedIdentifier, lockOptions, jsCallback.toJS);
    // A timeout abort will throw an exception which needs to be handled.
    // There should not be any other unhandled lock errors.
    promise.toDart.catchError((error) => null);
    return gotLock.future;
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
