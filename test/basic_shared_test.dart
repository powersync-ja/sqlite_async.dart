import 'dart:async';
import 'package:sqlite_async/sqlite3_common.dart';
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
      // Uncomment this to break this test
      // await db.close();
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

    test('should allow resuming transaction after errors', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);
      SqliteWriteContext? savedTx;
      await db.writeTransaction((tx) async {
        savedTx = tx;
        var caught = false;
        try {
          // This error does not rollback the transaction
          await tx.execute('NOT A VALID STATEMENT');
        } catch (e) {
          // Ignore
          caught = true;
        }
        expect(caught, equals(true));

        expect(await tx.getAutoCommit(), equals(false));
        expect(tx.closed, equals(false));

        final rs = await tx.execute(
            'INSERT INTO test_data(description) VALUES(?) RETURNING description',
            ['Test Data']);
        expect(rs.rows[0], equals(['Test Data']));
      });
      expect(await savedTx!.getAutoCommit(), equals(true));
      expect(savedTx!.closed, equals(true));
    });

    test('should properly report errors in transactions', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);

      var tp = db.writeTransaction((tx) async {
        await tx.execute(
            'INSERT OR ROLLBACK INTO test_data(id, description) VALUES(?, ?)',
            [1, 'test1']);
        await tx.execute(
            'INSERT OR ROLLBACK INTO test_data(id, description) VALUES(?, ?)',
            [2, 'test2']);
        expect(await tx.getAutoCommit(), equals(false));
        try {
          await tx.execute(
              'INSERT OR ROLLBACK INTO test_data(id, description) VALUES(?, ?)',
              [2, 'test3']);
        } catch (e) {
          // Ignore
        }

        expect(await tx.getAutoCommit(), equals(true));
        expect(tx.closed, equals(false));

        // Will not be executed because of the above rollback
        await tx.execute(
            'INSERT OR ROLLBACK INTO test_data(id, description) VALUES(?, ?)',
            [4, 'test4']);
      });

      // The error propagates up to the transaction
      await expectLater(
          tp,
          throwsA((e) =>
              e is SqliteException &&
              e.message
                  .contains('Transaction rolled back by earlier statement')));

      expect(await db.get('SELECT count() count FROM test_data'),
          equals({'count': 0}));

      // Check that we can open another transaction afterwards
      await db.writeTransaction((tx) async {});
    });
  });
}

// For some reason, future.ignore() doesn't actually ignore errors in these tests.
void ignore(Future future) {
  future.then((_) {}, onError: (_) {});
}
