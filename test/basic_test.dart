import 'dart:async';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:sqlite_async/mutex.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/expect.dart';
import 'package:test/test.dart';

import 'util.dart';

void main() {
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
      final db =
          SqliteDatabase.withFactory(testFactory(path: path), maxReaders: 3);
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
        }, throwsA((e) => e is LockError && e.message.contains('tx.execute')));
      });
    });

    test('should not allow read-only db calls within transaction callback',
        () async {
      final db = await setupDatabase(path: path);
      await createTables(db);

      await db.writeTransaction((tx) async {
        // This uses a different connection, so it _could_ work.
        // But it's likely unintentional and could cause weird bugs, so we don't
        // allow it by default.
        await expectLater(() async {
          await db.getAll('SELECT * FROM test_data');
        }, throwsA((e) => e is LockError && e.message.contains('tx.getAll')));
      });

      await db.readTransaction((tx) async {
        // This does actually attempt a lock on the same connection, so it
        // errors.
        // This also exposes an interesting test case where the read transaction
        // opens another connection, but doesn't use it.
        await expectLater(() async {
          await db.getAll('SELECT * FROM test_data');
        }, throwsA((e) => e is LockError && e.message.contains('tx.getAll')));
      });
    });

    test('should not allow read-only db calls within lock callback', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);
      // Locks - should behave the same as transactions above

      await db.writeLock((tx) async {
        await expectLater(() async {
          await db.getOptional('SELECT * FROM test_data');
        },
            throwsA(
                (e) => e is LockError && e.message.contains('tx.getOptional')));
      });

      await db.readLock((tx) async {
        await expectLater(() async {
          await db.getOptional('SELECT * FROM test_data');
        },
            throwsA(
                (e) => e is LockError && e.message.contains('tx.getOptional')));
      });
    });

    test(
        'should allow read-only db calls within transaction callback in separate zone',
        () async {
      final db = await setupDatabase(path: path);
      await createTables(db);

      // Get a reference to the parent zone (outside the transaction).
      final zone = Zone.current;

      // Each of these are fine, since it could use a separate connection.
      // Note: In highly concurrent cases, it could exhaust the connection pool and cause a deadlock.

      await db.writeTransaction((tx) async {
        // Use the parent zone to avoid the "recursive lock" error.
        await zone.fork().run(() async {
          await db.getAll('SELECT * FROM test_data');
        });
      });

      await db.readTransaction((tx) async {
        await zone.fork().run(() async {
          await db.getAll('SELECT * FROM test_data');
        });
      });

      await db.readTransaction((tx) async {
        await zone.fork().run(() async {
          await db.execute('SELECT * FROM test_data');
        });
      });

      // Note: This would deadlock, since it shares a global write lock.
      // await db.writeTransaction((tx) async {
      //   await zone.fork().run(() async {
      //     await db.execute('SELECT * FROM test_data');
      //   });
      // });
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
        ignore(tx.execute(
            'INSERT OR ROLLBACK INTO test_data(id, description) VALUES(?, ?)',
            [4, 'test4']));
      });

      // The error propagates up to the transaction
      await expectLater(
          tp,
          throwsA((e) =>
              e is sqlite.SqliteException &&
              e.message
                  .contains('Transaction rolled back by earlier statement') &&
              e.message.contains('UNIQUE constraint failed')));

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

    test('should handle normal errors', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);
      Error? caughtError;
      final syntheticError = ArgumentError('foobar');
      await db.computeWithDatabase<void>((db) async {
        throw syntheticError;
      }).catchError((error) {
        caughtError = error;
      });
      expect(caughtError.toString(), equals(syntheticError.toString()));

      // Check that we can still continue afterwards
      final computed = await db.computeWithDatabase((db) async {
        return 5;
      });
      expect(computed, equals(5));
    });

    test('should handle uncaught errors', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);
      Object? caughtError;
      await db.computeWithDatabase<void>((db) async {
        Future<void> asyncCompute() async {
          throw ArgumentError('uncaught async error');
        }

        asyncCompute();
      }).catchError((error) {
        caughtError = error;
      });
      // The specific error message may change
      expect(
          caughtError.toString(),
          equals(
              "IsolateError in sqlite-writer: Invalid argument(s): uncaught async error"));

      // Check that we can still continue afterwards
      final computed = await db.computeWithDatabase((db) async {
        return 5;
      });
      expect(computed, equals(5));
    });

    test('should handle uncaught errors in read connections', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);
      for (var i = 0; i < 10; i++) {
        Object? caughtError;

        await db.readTransaction((ctx) async {
          await ctx.computeWithDatabase((db) async {
            Future<void> asyncCompute() async {
              throw ArgumentError('uncaught async error');
            }

            asyncCompute();
          });
        }).catchError((error) {
          caughtError = error;
        });
        // The specific message may change
        expect(
            caughtError.toString(),
            matches(RegExp(
                r'IsolateError in sqlite-\d+: Invalid argument\(s\): uncaught async error')));
      }

      // Check that we can still continue afterwards
      final computed = await db.readTransaction((ctx) async {
        return await ctx.computeWithDatabase((db) async {
          return 5;
        });
      });
      expect(computed, equals(5));
    });

    test('should allow resuming transaction after errors', () async {
      final db = await setupDatabase(path: path);
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

    test('closing', () async {
      // Test race condition in SqliteConnectionPool:
      // 1. Open two concurrent queries, which opens two connection.
      // 2. Second connection takes longer to open than first.
      // 3. Call db.close().
      // 4. Now second connection is ready. Second query has two connections to choose from.
      // 5. However, first connection is closed, so it's removed from the pool.
      // 6. Triggers `Concurrent modification during iteration: Instance(length:1) of '_GrowableList'`
      final db =
          SqliteDatabase.withFactory(testFactory(path: path, initStatements: [
        // Second connection to sleep more than first connection
        'SELECT test_sleep(test_connection_number() * 10)'
      ]));
      await db.initialize();

      final future1 = db.get('SELECT test_sleep(10) as sleep');
      final future2 = db.get('SELECT test_sleep(10) as sleep');

      await db.close();

      await future1;
      await future2;
    });
  });
}

// For some reason, future.ignore() doesn't actually ignore errors in these tests.
void ignore(Future future) {
  future.then((_) {}, onError: (_) {});
}
