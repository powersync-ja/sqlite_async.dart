import 'dart:io';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import 'util.dart';

void main() {
  group('Close Tests', () {
    late String path;

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);
    });

    tearDown(() async {
      await cleanDb(path: path);
    });

    createTables(SqliteDatabase db) async {
      await db.transaction((tx) async {
        await tx.execute(
            'CREATE TABLE test_data(id INTEGER PRIMARY KEY AUTOINCREMENT, description TEXT)');
      });
    }

    test('Open and close', () async {
      // Test that the journal files are properly deleted after closing.
      // If the write connection is closed before the read connections, that is
      // not the case.

      final db = await setupDatabase(path: path);
      await createTables(db);

      await db.execute(
          'INSERT INTO test_data(description) VALUES(?)', ['Test Data']);
      await db.getAll('SELECT * FROM test_data');

      expect(await File('$path-wal').exists(), equals(true));
      expect(await File('$path-shm').exists(), equals(true));

      await db.close();

      expect(await File(path).exists(), equals(true));

      expect(await File('$path-wal').exists(), equals(false));
      expect(await File('$path-shm').exists(), equals(false));

      expect(await File('$path-journal').exists(), equals(false));
    });
  });
}
