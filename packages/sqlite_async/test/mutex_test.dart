import 'dart:async';
import 'dart:math';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

void main() {
  group('Shared Mutex Tests', () {
    test('Queue exclusive operations', () async {
      final m = Mutex();
      final collection = List.generate(10, (index) => index);
      final results = <int>[];

      final futures = collection.map((element) async {
        return m.lock(() async {
          // Simulate some asynchronous work
          await Future.delayed(Duration(milliseconds: Random().nextInt(100)));
          results.add(element);
          return element;
        });
      }).toList();

      // Await all the promises
      await Future.wait(futures);

      // Check if the results are in ascending order
      expect(results, equals(collection));
    });
  });

  test('Timeout should throw a LockError', () async {
    final m = Mutex();
    m.lock(() async {
      await Future.delayed(Duration(milliseconds: 300));
    });

    await expectLater(
        m.lock(() async {
          print('This should not get executed');
        }, timeout: Duration(milliseconds: 200)),
        throwsA((e) =>
            e is TimeoutException &&
            e.message!.contains('Failed to acquire lock')));
  });

  test('In-time timeout should function normally', () async {
    final m = Mutex();
    final results = [];
    m.lock(() async {
      await Future.delayed(Duration(milliseconds: 100));
      results.add(1);
    });

    await m.lock(() async {
      results.add(2);
    }, timeout: Duration(milliseconds: 200));

    expect(results, equals([1, 2]));
  });

  test('Different Mutex instances should cause separate locking', () async {
    final m1 = Mutex();
    final m2 = Mutex();

    final results = [];
    final p1 = m1.lock(() async {
      await Future.delayed(Duration(milliseconds: 300));
      results.add(1);
    });

    final p2 = m2.lock(() async {
      results.add(2);
    });

    await p1;
    await p2;
    expect(results, equals([2, 1]));
  });
}
