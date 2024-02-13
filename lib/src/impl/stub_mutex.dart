import 'package:sqlite_async/src/common/mutex.dart';

class MutexImpl extends Mutex {
  @override
  Future<void> close() {
    throw UnimplementedError();
  }

  @override
  Future<T> lock<T>(Future<T> Function() callback, {Duration? timeout}) {
    throw UnimplementedError();
  }
}
