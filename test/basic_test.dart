import 'dart:math';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'util.dart';

void main() {
  setupLogger();

  group('Basic Tests', () {
    late String path;

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);
    });

    tearDown(() async {
      await cleanDb(path: path);
    });

    createTables(SqliteDatabase db) async {
      await db.writeTransaction((tx) async {
        await tx.execute(
            'CREATE TABLE test_data(id INTEGER PRIMARY KEY AUTOINCREMENT, description TEXT)');
      });
    }

    test('Basic Setup', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);

      await db.execute(
          'INSERT INTO test_data(description) VALUES(?)', ['Test Data']);
      final result = await db.get('SELECT description FROM test_data');
      expect(result, equals({'description': 'Test Data'}));
      expect(
          await db.execute('PRAGMA journal_mode'),
          equals([
            {'journal_mode': 'wal'}
          ]));
      expect(
          await db.execute('PRAGMA locking_mode'),
          equals([
            {'locking_mode': 'normal'}
          ]));
    });

    // Manually verified
    test('Concurrency', () async {
      final db = SqliteDatabase.withFactory(
          openFactory: testFactory(path: path), maxReaders: 3);
      await db.initialize();
      await createTables(db);

      print("${DateTime.now()} start");
      var futures = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map((i) => db.get(
          'SELECT ? as i, test_sleep(?) as sleep, test_connection_name() as connection',
          [i, 5 + Random().nextInt(10)]));
      await for (var result in Stream.fromFutures(futures)) {
        print("${DateTime.now()} $result");
      }
    });

    test('read-only transactions', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);

      // Can read
      await db.getAll("WITH test AS (SELECT 1 AS one) SELECT * FROM test");

      // Cannot write
      await expectLater(() async {
        await db
            .getAll('INSERT INTO test_data(description) VALUES(?)', ['test']);
      },
          throwsA((e) =>
              e is sqlite.SqliteException &&
              e.message
                  .contains('attempt to write in a read-only transaction')));

      // Can use WITH ... SELECT
      await db.getAll("WITH test AS (SELECT 1 AS one) SELECT * FROM test");

      // Cannot use WITH .... INSERT
      await expectLater(() async {
        await db.getAll(
            "WITH test AS (SELECT 1 AS one) INSERT INTO test_data(description) SELECT one FROM test");
      },
          throwsA((e) =>
              e is sqlite.SqliteException &&
              e.message
                  .contains('attempt to write in a read-only transaction')));

      await db.writeTransaction((tx) async {
        // Within a write transaction, this is fine
        await tx.getAll(
            'INSERT INTO test_data(description) VALUES(?) RETURNING *',
            ['test']);
      });
    });

    test('should not allow direct db calls within a transaction callback',
        () async {
      final db = await setupDatabase(path: path);
      await createTables(db);

      await db.writeTransaction((tx) async {
        await expectLater(() async {
          await db.execute(
              'INSERT INTO test_data(description) VALUES(?)', ['test']);
        }, throwsA((e) => e is AssertionError));
      });
    });

    test('does allow read-only db calls within transaction callback', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);

      await db.writeTransaction((tx) async {
        // This uses a different connection, so it's fine.
        // Perhaps we should warn on this, since it's likely unintentional?
        await db.getAll('SELECT * FROM test_data');
      });

      await db.readTransaction((tx) async {
        // This does actually attempt a lock on the same connection, so it
        // errors.
        // This also exposes an interesting test case where the read transaction
        // opens another connection, but doesn't use it.
        await expectLater(() async {
          await db.getAll('SELECT * FROM test_data');
        }, throwsA((e) => e is AssertionError));
      });
    });

    test('does allow read-only db calls within lock callback', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);
      // Locks - should behave the same as transactions above

      await db.writeLock((tx) async {
        await db.getAll('SELECT * FROM test_data');
      });

      await db.readLock((tx) async {
        await expectLater(() async {
          await db.getAll('SELECT * FROM test_data');
        }, throwsA((e) => e is AssertionError));
      });
    });

    test('should allow PRAMGAs', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);
      // Not allowed in transactions, but does work as a direct statement.
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      await db.execute('VACUUM');
    });

    test('should allow ignoring errors', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);

      ignore(db.execute(
          'INSERT INTO test_data(description) VALUES(json(?))', ['test3']));
    });

    test('should properly report errors in transactions', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);

      var tp = db.writeTransaction((tx) async {
        tx.execute('INSERT INTO test_data(description) VALUES(?)', ['test1']);
        tx.execute('INSERT INTO test_data(description) VALUES(?)', ['test2']);
        ignore(tx.execute('INSERT INTO test_data(description) VALUES(json(?))',
            ['test3'])); // Errors
        // Will not be executed because of the above error
        ignore(tx.execute(
            'INSERT INTO test_data(description) VALUES(?) RETURNING *',
            ['test4']));
      });

      // The error propagates up to the transaction
      await expectLater(tp, throwsA((e) => e is sqlite.SqliteException));

      expect(await db.get('SELECT count() count FROM test_data'),
          equals({'count': 0}));

      // Check that we can open another transaction afterwards
      await db.writeTransaction((tx) async {});
    });

    test('should error on dangling transactions', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);
      await expectLater(() async {
        await db.execute('BEGIN');
      }, throwsA((e) => e is sqlite.SqliteException));
    });
  });
}

// For some reason, future.ignore() doesn't actually ignore errors in these tests.
void ignore(Future future) {
  future.then((_) {}, onError: (_) {});
}
