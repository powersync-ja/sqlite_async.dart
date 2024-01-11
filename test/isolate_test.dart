import 'dart:isolate';

import 'package:test/test.dart';
import 'package:sqlite_async/src/database/native/native_sqlite_database.dart';

import 'util.dart';

void main() {
  group('Isolate Tests', () {
    late String path;

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);
    });

    tearDown(() async {
      await cleanDb(path: path);
    });

    test('Basic Isolate usage', () async {
      final db = await setupDatabase(path: path) as SqliteDatabase;
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
