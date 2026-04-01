import 'dart:async';

import 'timeouts.dart';

/// An asynchronous mutex.
abstract interface class Mutex {
  /// Creates a simple mutex instance that can't be shared between tabs or
  /// isolates.
  factory Mutex.simple() = _SimpleMutex;

  /// Runs [callback] in a critical section.
  ///
  /// If [abortTrigger] completes before the critical section was entered, an
  /// [AbortException] is thrown and [callback] will not be invoked.
  Future<T> lock<T>(Future<T> Function() callback,
      {Future<void>? abortTrigger});
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
  Future<void>? last;

  // Hack to make sure the Mutex is not copied to another isolate.
  // ignore: unused_field
  final Finalizer _f = Finalizer((_) {});

  @override
  Future<T> lock<T>(Future<T> Function() callback,
      {Future<void>? abortTrigger}) async {
    if (Zone.current[this] != null) {
      throw LockError('Recursive lock is not allowed');
    }
    var zone = Zone.current.fork(zoneValues: {this: true});

    return zone.run(() async {
      final prev = last;
      var previousDidComplete = false;

      final completer = Completer<void>.sync();
      last = completer.future;
      try {
        // If there is a previous running block, wait for it
        if (prev != null) {
          final prevOrAbort = Completer<void>.sync();

          prev.then((_) {
            previousDidComplete = true;
            if (!prevOrAbort.isCompleted) prevOrAbort.complete();
          });
          if (abortTrigger != null) {
            abortTrigger.whenComplete(() {
              if (!prevOrAbort.isCompleted) {
                prevOrAbort.completeError(
                    AbortException('lock'), StackTrace.current);
              }
            });
          }

          await prevOrAbort.future;
        }

        // Run the function and return the result
        return await callback();
      } finally {
        // Cleanup
        // waiting for the previous task to be done in case of timeout
        void complete() {
          // Only mark it unlocked when the last one completes
          if (identical(last, completer.future)) {
            last = null;
          }
          completer.complete();
        }

        // In case of timeout, wait for the previous one to complete too
        // before marking this task as complete
        if (prev != null && !previousDidComplete) {
          // But we still return immediately
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
