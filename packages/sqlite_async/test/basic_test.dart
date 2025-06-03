import 'dart:async';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();
const _isDart2Wasm = bool.fromEnvironment('dart.tool.dart2wasm');

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

    test('should not delete data on close', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);

      await db
          .execute('INSERT INTO test_data(description) VALUES(?)', ['test']);

      final initialItems = await db.getAll('SELECT * FROM test_data');
      expect(initialItems.rows.length, greaterThan(0));

      await db.close();

      final db2 = await testUtils.setupDatabase(path: path);
      // This could also be a get call with an exception
      final table2 = await db2.getAll(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='test_data';");
      expect(table2.rows.length, greaterThan(0),
          reason: "Table should be persisted from last connection");

      await db2.close();
    });

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

    test(
      'should properly report errors in transactions',
      () async {
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
      },
      skip: _isDart2Wasm
          ? 'Fails due to compiler bug, https://dartbug.com/59981'
          : null,
    );

    test('reports exceptions as SqliteExceptions', () async {
      final db = await testUtils.setupDatabase(path: path);
      await expectLater(
        db.get('SELECT invalid_statement;'),
        throwsA(
          isA<SqliteException>()
              .having((e) => e.causingStatement, 'causingStatement',
                  'SELECT invalid_statement;')
              .having((e) => e.extendedResultCode, 'extendedResultCode', 1),
        ),
      );
    });

    test('can use raw database instance', () async {
      final factory = await testUtils.testFactory();
      final raw = await factory.openDatabaseForSingleConnection();
      // Creating a fuction ensures that this database is actually used - if
      // a connection were set up in a background isolate, it wouldn't have this
      // function.
      raw.createFunction(
          functionName: 'my_function', function: (args) => 'test');

      final db = SqliteDatabase.singleConnection(
          SqliteConnection.synchronousWrapper(raw));
      await createTables(db);

      expect(db.updates, emits(UpdateNotification({'test_data'})));
      await db
          .execute('INSERT INTO test_data(description) VALUES (my_function())');

      expect(await db.get('SELECT description FROM test_data'),
          {'description': 'test'});
    });

    test('respects lock timeouts', () async {
      // Unfortunately this test can't use fakeAsync because it uses actual
      // lock APIs on the web.
      final db = await testUtils.setupDatabase(path: path);
      final lockAcquired = Completer();

      final completion = db.writeLock((context) async {
        lockAcquired.complete();
        await Future.delayed(const Duration(seconds: 1));
      });

      await lockAcquired.future;
      await expectLater(
        () => db.writeLock(
            lockTimeout: Duration(milliseconds: 200), (_) async => {}),
        throwsA(isA<TimeoutException>()),
      );

      await completion;
    }, onPlatform: {
      'browser': Skip(
        'Web locks are managed with a shared worker, which does not support timeouts',
      )
    });
  });
}

// For some reason, future.ignore() doesn't actually ignore errors in these tests.
void ignore(Future future) {
  future.then((_) {}, onError: (_) {});
}
