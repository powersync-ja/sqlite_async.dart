import 'dart:async';
import 'package:sqlite_async/mutex.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

void main() {
  group('Shared Basic Tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    tearDown(() async {
      await testUtils.cleanDb(path: path);
    });

    createTables(SqliteDatabase db) async {
      await db.writeTransaction((tx) async {
        await tx.execute(
            'CREATE TABLE test_data(id INTEGER PRIMARY KEY AUTOINCREMENT, description TEXT)');
      });
    }

    test('should not allow direct db calls within a transaction callback',
        () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);

      await db.writeTransaction((tx) async {
        await expectLater(() async {
          await db.execute(
              'INSERT INTO test_data(description) VALUES(?)', ['test']);
        }, throwsA((e) => e is LockError && e.message.contains('tx.execute')));
      });
    });

    test('should allow PRAMGAs', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);
      // Not allowed in transactions, but does work as a direct statement.
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      await db.execute('VACUUM');
    });

    test('should allow ignoring errors', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);

      ignore(db.execute(
          'INSERT INTO test_data(description) VALUES(json(?))', ['test3']));
    });

    test('should handle normal errors', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);
      Error? caughtError;
      final syntheticError = ArgumentError('foobar');
      await db.writeLock<void>((db) async {
        throw syntheticError;
      }).catchError((error) {
        caughtError = error;
      });
      expect(caughtError.toString(), equals(syntheticError.toString()));

      // Check that we can still continue afterwards
      final computed = await db.writeLock((db) async {
        return 5;
      });
      expect(computed, equals(5));
    });
  });
}

// For some reason, future.ignore() doesn't actually ignore errors in these tests.
void ignore(Future future) {
  future.then((_) {}, onError: (_) {});
}
