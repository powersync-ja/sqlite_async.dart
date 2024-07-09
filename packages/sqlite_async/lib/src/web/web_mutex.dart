import 'dart:async';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:mutex/mutex.dart' as mutex;
import 'package:sqlite_async/src/common/mutex.dart';
import 'dart:js_interop';
import 'package:web/web.dart';

@JS('navigator')
external Navigator get _navigator;

@JS('AbortController')
external AbortController get _abortController;

/// Web implementation of [Mutex]
class MutexImpl implements Mutex {
  late final mutex.Mutex fallback;
  String? identifier;
  String _resolvedIdentifier;

  MutexImpl({this.identifier})

      /// On web a lock name is required for Navigator locks.
      /// Having exclusive Mutex instances requires a somewhat unique lock name.
      /// This provides a best effort unique identifier, if no identifier is provided.
      /// This should be fine for most use cases:
      ///    - The uuid package could be added for better uniqueness if required.
      ///    - This would add another package dependency to `sqlite_async` which is potentially unnecessary at this point.
      /// An identifier should be supplied for better exclusion.
      : _resolvedIdentifier = identifier ??
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

  Future<T> _fallbackLock<T>(Future<T> Function() callback,
      {Duration? timeout}) {
    final completer = Completer<T>();
    // Need to implement timeout manually for this
    bool isTimedOut = false;
    bool lockObtained = false;
    if (timeout != null) {
      Future.delayed(timeout, () {
        isTimedOut = true;
        if (lockObtained == false) {
          completer.completeError(LockError('Timeout reached'));
        }
      });
    }

    fallback.protect(() async {
      try {
        if (isTimedOut) {
          // Don't actually run logic
          return;
        }
        lockObtained = true;
        final result = await callback();
        completer.complete(result);
      } catch (ex) {
        completer.completeError(ex);
      }
    });

    return completer.future;
  }

  Future<T> _webLock<T>(Future<T> Function() callback, {Duration? timeout}) {
    final completer = Completer<T>();
    // Navigator locks can be timed out by using an AbortSignal
    final controller = AbortController();

    bool lockAcquired = false;
    if (timeout != null) {
      // Can't really abort the `delayed` call easily :(
      Future.delayed(timeout, () {
        if (lockAcquired == true) {
          return;
        }
        completer.completeError(LockError('Timeout reached'));
        controller.abort('Timeout'.toJS);
      });
    }

    JSPromise jsCallback(JSAny lock) {
      lockAcquired = true;
      callback().then((value) {
        completer.complete(value);
      }).catchError((error) {
        completer.completeError(error);
      });
      return completer.future.toJS;
    }

    final lockOptions = JSObject();
    lockOptions['signal'] = controller.signal;
    _navigator.locks.request(_resolvedIdentifier, lockOptions, jsCallback.toJS);

    return completer.future;
  }

  @override
  Mutex open() {
    return this;
  }
}
