@TestOn('!browser')
library;

import 'dart:async';

import 'package:sqlite3/common.dart' as sqlite;
import 'package:sqlite_async/native.dart';
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
        await testUtils.testFactory(
            path: path, options: SqliteOptions(maxReaders: 3)),
      );
      await db.initialize();
      await createTables(db);

      final hasConcurrentTransactions = Completer();
      final releaseConnections = Completer();
      var startedTransactions = 0;
      for (var i = 0; i < 3; i++) {
        final tx = db.readTransaction((tx) async {
          startedTransactions++;
          if (startedTransactions == 3) {
            hasConcurrentTransactions.complete();
          }

          await releaseConnections.future;
          expect(await tx.getAll('SELECT * FROM test_data'), hasLength(0));
        });
        expectLater(tx, completes);
      }

      await hasConcurrentTransactions.future;

      // Ensure we can write while read transactions are active.
      await db
          .execute('INSERT INTO test_data (description) VALUES (?)', ['test']);
      releaseConnections.complete();
    });

    test('prevent opening new readers while in withAllConnections', () async {
      final db = SqliteDatabase.withFactory(
        await testUtils.testFactory(
            path: path, options: SqliteOptions(maxReaders: 3)),
      );
      await db.initialize();
      await createTables(db);

      final hasAllConnectionsCompleter = Completer<void>();
      final withAllConnectionsCompleter = Completer<void>();

      final withAllConnsFut = db.withAllConnections((writer, readers) async {
        expect(readers.length, 3);
        hasAllConnectionsCompleter.complete();

        await withAllConnectionsCompleter.future;
      });

      await hasAllConnectionsCompleter.future;

      // Start a reader that gets the contents of the shared file
      bool readFinished = false;
      final someReadFut = db.get('SELECT 1', []).then((r) {
        readFinished = true;
        return r;
      });

      // The withAllConnections should prevent the reader from opening
      await Future.delayed(const Duration(milliseconds: 100));
      expect(readFinished, isFalse);

      // Free all the locks
      withAllConnectionsCompleter.complete();
      await withAllConnsFut;

      await someReadFut;
      expect(readFinished, isTrue);
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
          throwsA(isA<sqlite.SqliteException>().having((e) => e.message,
              'message', contains('attempt to write a readonly database'))));

      // Can use WITH ... SELECT
      await db.getAll("WITH test AS (SELECT 1 AS one) SELECT * FROM test");

      // Cannot use WITH .... INSERT
      await expectLater(() async {
        await db.getAll(
            "WITH test AS (SELECT 1 AS one) INSERT INTO test_data(description) SELECT one FROM test");
      },
          throwsA(isA<sqlite.SqliteException>().having((e) => e.message,
              'message', contains('attempt to write a readonly database'))));

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

      await expectLater(
          db.execute('BEGIN'), throwsA((e) => e is sqlite.SqliteException));
      expect(await db.getAutoCommit(), isTrue);

      await expectLater(db.writeLock((ctx) async {
        expect(await ctx.getAutoCommit(), isTrue);
        await ctx.execute('BEGIN');
        expect(await ctx.getAutoCommit(), isFalse);
      }), throwsA(isA<sqlite.SqliteException>()));

      expect(await db.getAutoCommit(), isTrue);
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
      expect(caughtError.toString(),
          equals("Invalid argument(s): uncaught async error"));

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
        expect(caughtError.toString(),
            contains('Invalid argument(s): uncaught async error'));
      }

      // Check that we can still continue afterwards
      final computed = await db.readTransaction((ctx) async {
        return await ctx.computeWithDatabase((db) async {
          return 5;
        });
      });
      expect(computed, equals(5));
    });

    test('lockTimeout', () async {
      final db = await testUtils.setupDatabase(
          path: path, options: SqliteOptions(maxReaders: 2));
      await db.initialize();

      final f1 = db.readTransaction((tx) async {
        await Future.delayed(const Duration(milliseconds: 100));
      }, lockTimeout: const Duration(milliseconds: 200));

      final f2 = db.readTransaction((tx) async {
        await Future.delayed(const Duration(milliseconds: 100));
      }, lockTimeout: const Duration(milliseconds: 200));

      // At this point, both read connections are in use
      await expectLater(() async {
        await db.readLock((tx) async {
          await tx.get('select 1');
        }, lockTimeout: const Duration(milliseconds: 2));
      }, throwsAbortException);

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

final class _InvalidPragmaOnOpenFactory extends NativeSqliteOpenFactory {
  _InvalidPragmaOnOpenFactory({required super.path});

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    return [
      'invalid syntax to fail open in test',
      ...super.pragmaStatements(options),
    ];
  }
}
