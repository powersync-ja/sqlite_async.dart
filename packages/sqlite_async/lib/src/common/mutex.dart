import 'dart:async';

/// An asynchronous mutex.
abstract interface class Mutex {
  /// Creates a simple mutex instance that can't be shared between tabs or
  /// isolates.
  factory Mutex.simple() = _SimpleMutex;

  /// timeout is a timeout for acquiring the lock, not for the callback
  Future<T> lock<T>(Future<T> Function() callback, {Duration? timeout});
}

class LockError extends Error {
  final String message;

  LockError(this.message);

  @override
  String toString() {
    return 'LockError: $message';
  }
}

/// Mutex maintains a queue of Future-returning functions that are executed
/// sequentially.
final class _SimpleMutex implements Mutex {
  Future<dynamic>? last;

  // Hack to make sure the Mutex is not copied to another isolate.
  // ignore: unused_field
  final Finalizer _f = Finalizer((_) {});

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
}
