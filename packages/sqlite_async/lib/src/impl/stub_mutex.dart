import 'package:sqlite_async/src/common/mutex.dart';

class MutexImpl implements Mutex {
  String? identifier;

  MutexImpl({this.identifier});

  @override
  Future<void> close() {
    throw UnimplementedError();
  }

  @override
  Future<T> lock<T>(Future<T> Function() callback, {Duration? timeout}) {
    throw UnimplementedError();
  }

  @override
  Mutex open() {
    throw UnimplementedError();
  }
}
