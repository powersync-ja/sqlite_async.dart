import 'package:sqlite_async/src/impl/mutex_impl.dart';

abstract class Mutex {
  factory Mutex() {
    return MutexImpl();
  }

  /// timeout is a timeout for acquiring the lock, not for the callback
  Future<T> lock<T>(Future<T> Function() callback, {Duration? timeout});

  /// Use [open] to get a [AbstractMutex] instance.
  /// This is mainly used for shared mutexes
  Mutex open() {
    return this;
  }

  /// Release resources used by the Mutex.
  ///
  /// Subsequent calls to [lock] may fail, or may never call the callback.
  Future<void> close();
}

class LockError extends Error {
  final String message;

  LockError(this.message);

  @override
  String toString() {
    return 'LockError: $message';
  }
}
