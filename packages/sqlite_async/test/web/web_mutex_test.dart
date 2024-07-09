import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import '../utils/test_utils_impl.dart';

final testUtils = TestUtils();

void main() {
  group('Web Mutex Tests', () {
    test('Web should share locking with identical identifiers', () async {
      final m1 = Mutex(identifier: 'sync');
      final m2 = Mutex(identifier: 'sync');

      final results = [];
      final p1 = m1.lock(() async {
        results.add(1);
      });

      final p2 = m2.lock(() async {
        results.add(2);
      });

      await p1;
      await p2;
      // It should be correctly ordered as if it was the same mutex
      expect(results, equals([1, 2]));
    });
  });
}
