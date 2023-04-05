// Adapted from:
//  https://github.com/tekartik/synchronized.dart
//  (MIT)
import 'dart:async';

import 'port_channel.dart';

abstract class Mutex {
  factory Mutex() {
    return SimpleMutex();
  }

  /// timeout is a timeout for acquiring the lock, not for the callback
  Future<T> lock<T>(Future<T> Function() callback, {Duration? timeout});

  /// Release resources used by the Mutex.
  ///
  /// Subsequent calls to [lock] may fail, or may never call the callback.
  Future<void> close();
}

/// Mutex maintains a queue of Future-returning functions that
/// are executed sequentially.
/// The internal lock is not shared across Isolates by default.
class SimpleMutex implements Mutex {
  // Adapted from https://github.com/tekartik/synchronized.dart/blob/master/synchronized/lib/src/basic_lock.dart

  Future<dynamic>? last;

  // Hack to make sure the Mutex is not copied to another isolate.
  // ignore: unused_field
  final Finalizer _f = Finalizer((_) {});

  SimpleMutex();

  bool get locked => last != null;

  _SharedMutexServer? _shared;

  @override
  Future<T> lock<T>(Future<T> Function() callback, {Duration? timeout}) async {
    if (Zone.current[this] != null) {
      throw LockError('Recursive lock is not allowed');
    }
    var zone = Zone.current.fork(zoneValues: {this: true});

    return zone.run(() async {
      final prev = last;
      final completer = Completer<void>.sync();
      last = completer.future;
      try {
        // If there is a previous running block, wait for it
        if (prev != null) {
          if (timeout != null) {
            // This could throw a timeout error
            try {
              await prev.timeout(timeout);
            } catch (error) {
              if (error is TimeoutException) {
                throw TimeoutException('Failed to acquire lock', timeout);
              } else {
                rethrow;
              }
            }
          } else {
            await prev;
          }
        }

        // Run the function and return the result
        return await callback();
      } finally {
        // Cleanup
        // waiting for the previous task to be done in case of timeout
        void complete() {
          // Only mark it unlocked when the last one complete
          if (identical(last, completer.future)) {
            last = null;
          }
          completer.complete();
        }

        // In case of timeout, wait for the previous one to complete too
        // before marking this task as complete
        if (prev != null && timeout != null) {
          // But we still returns immediately
          prev.then((_) {
            complete();
          }).ignore();
        } else {
          complete();
        }
      }
    });
  }

  @override
  Future<void> close() async {
    _shared?.close();
    await lock(() async {});
  }

  /// Get a serialized instance that can be passed over to a different isolate.
  SerializedMutex get shared {
    _shared ??= _SharedMutexServer._withMutex(this);
    return _shared!.serialized;
  }
}

/// Serialized version of a Mutex, can be passed over to different isolates.
/// Use [open] to get a [SharedMutex] instance.
///
/// Uses a [SendPort] to communicate with the source mutex.
class SerializedMutex {
  final SerializedPortClient client;

  const SerializedMutex(this.client);

  SharedMutex open() {
    return SharedMutex._(client.open());
  }
}

/// Mutex instantiated from a source mutex, potentially in a different isolate.
///
/// Uses a [SendPort] to communicate with the source mutex.
class SharedMutex implements Mutex {
  final ChildPortClient client;

  SharedMutex._(this.client);

  @override
  Future<T> lock<T>(Future<T> Function() callback, {Duration? timeout}) async {
    if (Zone.current[this] != null) {
      throw LockError('Recursive lock is not allowed');
    }
    return runZoned(() async {
      await _acquire(timeout: timeout);
      try {
        final T result = await callback();
        return result;
      } finally {
        _unlock();
      }
    }, zoneValues: {this: true});
  }

  _unlock() {
    client.fire(const _UnlockMessage());
  }

  Future<void> _acquire({Duration? timeout}) async {
    final lockFuture = client.post(const _AcquireMessage());
    bool timedout = false;

    var handledLockFuture = lockFuture.then((_) {
      if (timedout) {
        _unlock();
        throw TimeoutException('Failed to acquire lock', timeout);
      }
    });

    if (timeout != null) {
      handledLockFuture =
          handledLockFuture.timeout(timeout).catchError((error, stacktrace) {
        timedout = true;
        if (error is TimeoutException) {
          throw TimeoutException('Failed to acquire SharedMutex lock', timeout);
        }
        throw error;
      });
    }
    return await handledLockFuture;
  }

  @override
  Future<void> close() async {
    client.close();
  }
}

/// Manages a [SerializedMutex], allowing a [Mutex] to be shared across isolates.
class _SharedMutexServer {
  Completer? unlock;
  late final SerializedMutex serialized;
  final Mutex mutex;

  late final PortServer server;

  _SharedMutexServer._withMutex(this.mutex) {
    server = PortServer((Object? arg) async {
      return await _handle(arg);
    });
    serialized = SerializedMutex(server.client());
  }

  Future<void> _handle(Object? arg) async {
    if (arg is _AcquireMessage) {
      var lock = Completer.sync();
      mutex.lock(() async {
        assert(unlock == null);
        unlock = Completer.sync();
        lock.complete();
        await unlock!.future;
        unlock = null;
      });
      await lock.future;
    } else if (arg is _UnlockMessage) {
      assert(unlock != null);
      unlock!.complete();
    }
  }

  void close() async {
    server.close();
  }
}

class _AcquireMessage {
  const _AcquireMessage();
}

class _UnlockMessage {
  const _UnlockMessage();
}

class LockError extends Error {
  final String message;

  LockError(this.message);

  @override
  String toString() {
    return 'LockError: $message';
  }
}
