import 'package:mutex/mutex.dart' as mutex;
import 'package:sqlite_async/src/common/mutex.dart';

class MutexImpl extends Mutex {
  late final mutex.Mutex m;

  MutexImpl() {
    m = mutex.Mutex();
  }

  @override
  Future<void> close() async {
    // TODO
  }

  @override
  Future<T> lock<T>(Future<T> Function() callback, {Duration? timeout}) {
    // TODO: use web navigator locks here
    return m.protect(callback);
  }
}
