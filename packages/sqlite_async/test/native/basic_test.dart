@TestOn('!browser')
library;

import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:sqlite3/common.dart' as sqlite;
import 'package:sqlite3/sqlite3.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import '../utils/test_utils_impl.dart';

final testUtils = TestUtils();

void main() {
  group('Basic Tests', () {
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

    test('Basic Setup', () async {
      final db = await testUtils.setupDatabase(path: path);
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
          await testUtils.testFactory(path: path),
          maxReaders: 3);
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

    test('with all connections', () async {
      final db = SqliteDatabase.withFactory(
          await testUtils.testFactory(path: path),
          maxReaders: 3);
      await db.initialize();
      await createTables(db);


      Future<Row> readWithRandomDelay(SqliteReadContext ctx, int id) async {
        return await ctx.get(
            'SELECT ? as i, test_sleep(?) as sleep, test_connection_name() as connection',
            [id, 5 + Random().nextInt(10)]);
      }

      // Warm up to spawn the max readers
      await Future.wait(
        [1, 2, 3, 4, 5, 6, 7, 8].map((i) => readWithRandomDelay(db, i)),
      );

      bool finishedWithAllConns = false;

      late Future<void> readsCalledWhileWithAllConnsRunning;

      print("${DateTime.now()} start");
      await db.withAllConnections((writer, readers) async {
        assert(readers.length == 3);

        // Run some reads during the block that they should run after the block finishes and releases
        // all locks
        readsCalledWhileWithAllConnsRunning = Future.wait(
          [1, 2, 3, 4, 5, 6, 7, 8].map((i) async {
            final r = await db.readLock((c) async {
              expect(finishedWithAllConns, isTrue);
              return await readWithRandomDelay(c, i);
            });
            print(
                "${DateTime.now()} After withAllConnections, started while running $r");
          }),
        );

        await Future.wait([
          writer.execute(
              "INSERT OR REPLACE INTO test_data(id, description) SELECT ? as i, test_sleep(?) || ' ' || test_connection_name() || ' 1 ' || datetime() as connection RETURNING *",
              [
                123,
                5 + Random().nextInt(20)
              ]).then((value) =>
              print("${DateTime.now()} withAllConnections writer done $value")),
          ...readers
              .mapIndexed((i, r) => readWithRandomDelay(r, i).then((results) {
                    print(
                        "${DateTime.now()} withAllConnections readers done $results");
                  }))
        ]);
      }).then((_) => finishedWithAllConns = true);

      await readsCalledWhileWithAllConnsRunning;
    });

    test('Concurren 2', () async {
      final db1 = await testUtils.setupDatabase(path: path, maxReaders: 3);
      final db2 = await testUtils.setupDatabase(path: path, maxReaders: 3);

      await db1.initialize();
      await createTables(db1);
      await db2.initialize();
      print("${DateTime.now()} start");

      var futures1 = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map((i) {
        return db1.execute(
            "INSERT OR REPLACE INTO test_data(id, description) SELECT ? as i, test_sleep(?) || ' ' || test_connection_name() || ' 1 ' || datetime() as connection RETURNING *",
            [
              i,
              5 + Random().nextInt(20)
            ]).then((value) => print("${DateTime.now()} $value"));
      }).toList();

      var futures2 = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map((i) {
        return db2.execute(
            "INSERT OR REPLACE INTO test_data(id, description) SELECT ? as i, test_sleep(?) || ' ' || test_connection_name() || ' 2 ' || datetime() as connection RETURNING *",
            [
              i,
              5 + Random().nextInt(20)
            ]).then((value) => print("${DateTime.now()} $value"));
      }).toList();
      await Future.wait(futures1);
      await Future.wait(futures2);
      print("${DateTime.now()} done");
    });

    test('read-only transactions', () async {
      final db = await testUtils.setupDatabase(path: path);
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

    test('should not allow read-only db calls within transaction callback',
        () async {
      final db = await testUtils.setupDatabase(path: path);
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
      final db = await testUtils.setupDatabase(path: path);
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
      final db = await testUtils.setupDatabase(path: path);
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

    test('should allow ignoring errors', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);

      ignore(db.execute(
          'INSERT INTO test_data(description) VALUES(json(?))', ['test3']));
    });

    test('should error on dangling transactions', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);
      await expectLater(() async {
        await db.execute('BEGIN');
      }, throwsA((e) => e is sqlite.SqliteException));
    });

    test('should handle uncaught errors', () async {
      final db = await testUtils.setupDatabase(path: path);
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
      final db = await testUtils.setupDatabase(path: path);
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

    test('closing', () async {
      // Test race condition in SqliteConnectionPool:
      // 1. Open two concurrent queries, which opens two connection.
      // 2. Second connection takes longer to open than first.
      // 3. Call db.close().
      // 4. Now second connection is ready. Second query has two connections to choose from.
      // 5. However, first connection is closed, so it's removed from the pool.
      // 6. Triggers `Concurrent modification during iteration: Instance(length:1) of '_GrowableList'`
      final db = SqliteDatabase.withFactory(
          await testUtils.testFactory(path: path, initStatements: [
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

    test('lockTimeout', () async {
      final db = await testUtils.setupDatabase(path: path, maxReaders: 2);
      await db.initialize();

      final f1 = db.readTransaction((tx) async {
        await tx.get('select test_sleep(100)');
      }, lockTimeout: const Duration(milliseconds: 200));

      final f2 = db.readTransaction((tx) async {
        await tx.get('select test_sleep(100)');
      }, lockTimeout: const Duration(milliseconds: 200));

      // At this point, both read connections are in use
      await expectLater(() async {
        await db.readLock((tx) async {
          await tx.get('select test_sleep(10)');
        }, lockTimeout: const Duration(milliseconds: 2));
      }, throwsA((e) => e is TimeoutException));

      await Future.wait([f1, f2]);
    });

    test('reports open error', () async {
      // Ensure that a db that fails to open doesn't report any unhandled
      // exceptions. This could happen when e.g. SQLCipher is used and the open
      // factory supplies a wrong key pragma (because a subsequent pragma to
      // change the journal mode then fails with a "not a database" error).
      final db =
          SqliteDatabase.withFactory(_InvalidPragmaOnOpenFactory(path: path));
      await expectLater(
        db.initialize(),
        throwsA(
          isA<Object>().having(
              (e) => e.toString(), 'toString()', contains('syntax error')),
        ),
      );
    });
  });
}

// For some reason, future.ignore() doesn't actually ignore errors in these tests.
void ignore(Future future) {
  future.then((_) {}, onError: (_) {});
}

class _InvalidPragmaOnOpenFactory extends DefaultSqliteOpenFactory {
  const _InvalidPragmaOnOpenFactory({required super.path});

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    return [
      'invalid syntax to fail open in test',
      ...super.pragmaStatements(options),
    ];
  }
}
