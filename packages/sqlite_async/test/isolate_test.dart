@TestOn('!browser')
library;

import 'dart:isolate';

import 'package:test/test.dart';

import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

void main() {
  group('Isolate Tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    tearDown(() async {
      await testUtils.cleanDb(path: path);
    });

    test('Basic Isolate usage', () async {
      final db = await testUtils.setupDatabase(path: path);
      final factory = db.isolateConnectionFactory();

      final result = await Isolate.run(() async {
        final db = factory.open();
        await db
            .execute('CREATE TABLE test_in_isolate(id INTEGER PRIMARY KEY)');
        return await db.get('SELECT count() as count FROM test_in_isolate');
      });
      expect(result, equals({'count': 0}));
    });
  });
}
