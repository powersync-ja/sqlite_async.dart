import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_sqlite_async/drift_sqlite_async.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import './utils/test_utils.dart';

class EmptyDatabase extends GeneratedDatabase {
  EmptyDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => [];

  @override
  int get schemaVersion => 1;
}

void main() {
  group('Basic Tests', () {
    late String path;
    late SqliteDatabase db;
    late SqliteAsyncDriftConnection connection;
    late EmptyDatabase dbu;

    createTables(SqliteDatabase db) async {
      await db.writeTransaction((tx) async {
        await tx.execute(
            'CREATE TABLE test_data(id INTEGER PRIMARY KEY AUTOINCREMENT, description TEXT)');
      });
    }

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);

      db = await setupDatabase(path: path);
      connection = SqliteAsyncDriftConnection(db);
      dbu = EmptyDatabase(connection);
      await createTables(db);
    });

    tearDown(() async {
      await dbu.close();
      await db.close();

      await cleanDb(path: path);
    });

    test('INSERT/SELECT', () async {
      final insertRowId = await dbu.customInsert(
          'INSERT INTO test_data(description) VALUES(?)',
          variables: [Variable('Test Data')]);
      expect(insertRowId, greaterThanOrEqualTo(1));

      final result = await dbu
          .customSelect('SELECT description FROM test_data')
          .getSingle();
      expect(result.data, equals({'description': 'Test Data'}));
    });

    test('INSERT RETURNING', () async {
      final row = await dbu.customSelect(
          'INSERT INTO test_data(description) VALUES(?) RETURNING *',
          variables: [Variable('Test Data')]).getSingle();
      expect(row.data['description'], equals('Test Data'));
    });

    test('Flat transaction', () async {
      await dbu.transaction(() async {
        await dbu.customInsert('INSERT INTO test_data(description) VALUES(?)',
            variables: [Variable('Test Data')]);

        // This runs outside the transaction - should not see the insert
        expect(await db.get('select count(*) as count from test_data'),
            equals({'count': 0}));

        // This runs in the transaction - should see the insert
        expect(
            (await dbu
                    .customSelect('select count(*) as count from test_data')
                    .getSingle())
                .data,
            equals({'count': 1}));
      });

      expect(await db.get('select count(*) as count from test_data'),
          equals({'count': 1}));
    });

    test('Flat transaction rollback', () async {
      final testException = Exception('abort');

      try {
        await dbu.transaction(() async {
          await dbu.customInsert('INSERT INTO test_data(description) VALUES(?)',
              variables: [Variable('Test Data')]);

          expect(await db.get('select count(*) as count from test_data'),
              equals({'count': 0}));

          throw testException;
        });

        // ignore: dead_code
        throw Exception('Exception expected');
      } catch (e) {
        expect(e, equals(testException));
      }

      // Rolled back - no data persisted
      expect(await db.get('select count(*) as count from test_data'),
          equals({'count': 0}));
    });

    test('Nested transaction', () async {
      await dbu.transaction(() async {
        await dbu.customInsert('INSERT INTO test_data(description) VALUES(?)',
            variables: [Variable('Test 1')]);

        await dbu.transaction(() async {
          await dbu.customInsert('INSERT INTO test_data(description) VALUES(?)',
              variables: [Variable('Test 2')]);
        });

        // This runs outside the transaction
        expect(await db.get('select count(*) as count from test_data'),
            equals({'count': 0}));
      });

      expect(await db.get('select count(*) as count from test_data'),
          equals({'count': 2}));
    });

    test('Nested transaction rollback', () async {
      final testException = Exception('abort');

      await dbu.transaction(() async {
        await dbu.customInsert('INSERT INTO test_data(description) VALUES(?)',
            variables: [Variable('Test 1')]);

        try {
          await dbu.transaction(() async {
            await dbu.customInsert(
                'INSERT INTO test_data(description) VALUES(?)',
                variables: [Variable('Test 2')]);

            throw testException;
          });

          // ignore: dead_code
          throw Exception('Exception expected');
        } catch (e) {
          expect(e, equals(testException));
        }

        await dbu.customInsert('INSERT INTO test_data(description) VALUES(?)',
            variables: [Variable('Test 3')]);

        // This runs outside the transaction
        expect(await db.get('select count(*) as count from test_data'),
            equals({'count': 0}));
      });

      expect(
          await db
              .getAll('select description from test_data order by description'),
          equals([
            {'description': 'Test 1'},
            {'description': 'Test 3'}
          ]));
    });

    test('Concurrent select', () async {
      var completer1 = Completer<void>();
      var completer2 = Completer<void>();

      final tx1 = dbu.transaction(() async {
        await dbu.customInsert('INSERT INTO test_data(description) VALUES(?)',
            variables: [Variable('Test Data')]);

        completer2.complete();

        // Stay in the transaction until the check below completed.
        await completer1.future;
      });

      await completer2.future;
      try {
        // This times out if concurrent select is not supported
        expect(
            (await dbu
                    .customSelect('select count(*) as count from test_data')
                    .getSingle()
                    .timeout(const Duration(milliseconds: 500)))
                .data,
            equals({'count': 0}));
      } finally {
        completer1.complete();
      }
      await tx1;

      expect(
          (await dbu
                  .customSelect('select count(*) as count from test_data')
                  .getSingle())
              .data,
          equals({'count': 1}));
    });
  });
}
