import 'package:sqlite_async/src/common/abstract_mutex.dart';

class Mutex extends AbstractMutex {
  @override
  Future<void> close() {
    throw UnimplementedError();
  }

  @override
  Future<T> lock<T>(Future<T> Function() callback, {Duration? timeout}) {
    throw UnimplementedError();
  }
}
