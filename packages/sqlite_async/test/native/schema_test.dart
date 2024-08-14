@TestOn('!browser')
import 'dart:async';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/src/utils/shared_utils.dart';
import 'package:test/test.dart';

import '../utils/test_utils_impl.dart';

final testUtils = TestUtils();

void main() {
  group('Schema Tests', () {
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
            'CREATE TABLE _customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)');
        await tx.execute(
            'CREATE TABLE _local_customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)');
        await tx
            .execute('CREATE VIEW customers AS SELECT * FROM _local_customers');
      });
    }

    updateTables(SqliteDatabase db) async {
      await db.writeTransaction((tx) async {
        await tx.execute('DROP VIEW IF EXISTS customers');
        await tx.execute('CREATE VIEW customers AS SELECT * FROM _customers');
      });
    }

    test('should refresh schema views', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);

      final customerTables =
          await getSourceTables(db, "select * from customers");
      expect(customerTables.contains('_local_customers'), true);
      await updateTables(db);

      // without this, source tables are outdated
      await db.refreshSchema();

      final updatedCustomerTables =
          await getSourceTables(db, "select * from customers");
      expect(updatedCustomerTables.contains('_customers'), true);
    });

    test('should complete refresh schema after transaction', () async {
      var completer1 = Completer<void>();
      var transactionCompleted = false;

      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);

      // Start a read transaction
      db.readTransaction((tx) async {
        completer1.complete();
        await tx.get('select test_sleep(2000)');

        transactionCompleted = true;
      });

      // Wait for the transaction to start
      await completer1.future;

      var refreshSchemaFuture = db.refreshSchema();

      // Setup check that refreshSchema completes after the transaction has completed
      var refreshAfterTransaction = false;
      refreshSchemaFuture.then((_) {
        if (transactionCompleted) {
          refreshAfterTransaction = true;
        }
      });

      await refreshSchemaFuture;

      expect(refreshAfterTransaction, isTrue,
          reason: 'refreshSchema completed before transaction finished');

      // Sanity check
      expect(transactionCompleted, isTrue,
          reason: 'Transaction did not complete as expected');
    });
  });
}

// For some reason, future.ignore() doesn't actually ignore errors in these tests.
void ignore(Future future) {
  future.then((_) {}, onError: (_) {});
}
