import 'dart:isolate';

import 'package:sqlite_async/src/native/native_isolate_mutex.dart';
import 'package:test/test.dart';

void main() {
  group('Mutex Tests', () {
    test('Closing', () async {
      // Test that locks are properly released when calling SharedMutex.close()
      // in in Isolate.
      // A timeout in this test indicates a likely error.
      for (var i = 0; i < 50; i++) {
        final mutex = SimpleMutex();
        final serialized = mutex.shared;

        final result = await Isolate.run(() async {
          return _lockInIsolate(serialized);
        });

        await mutex.lock(() async {});

        expect(result, equals(5));
      }
    });
  }, timeout: const Timeout(Duration(milliseconds: 5000)));
}

Future<Object> _lockInIsolate(
  SerializedMutex smutex,
) async {
  final mutex = smutex.open();
  // Start a "thread" that repeatedly takes a lock
  _infiniteLock(mutex).ignore();
  await Future.delayed(const Duration(milliseconds: 10));
  // Then close the mutex while the above loop is running.
  await mutex.close();

  return 5;
}

Future<void> _infiniteLock(SharedMutex mutex) async {
  while (true) {
    await mutex.lock(() async {
      await Future.delayed(const Duration(milliseconds: 1));
    });
  }
}
