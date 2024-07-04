import 'package:mutex/mutex.dart' as mutex;
import 'package:sqlite_async/src/common/mutex.dart';

/// Web implementation of [Mutex]
/// This should use `navigator.locks` in future
class MutexImpl implements Mutex {
  late final mutex.Mutex m;

  MutexImpl() {
    m = mutex.Mutex();
  }

  @override
  Future<void> close() async {
    // This isn't relevant for web at the moment.
  }

  @override
  Future<T> lock<T>(Future<T> Function() callback, {Duration? timeout}) {
    // Note this lock is only valid in a single web tab
    return m.protect(callback);
  }

  @override
  Mutex open() {
    return this;
  }
}
