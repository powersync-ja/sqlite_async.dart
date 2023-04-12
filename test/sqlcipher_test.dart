import 'dart:async';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:sqlite_async/mutex.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import 'util.dart';

void main() {
  group('SQLCipher Tests', () {
    late String path;

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);
    });

    tearDown(() async {
      // await cleanDb(path: path);
    });

    createTables(SqliteDatabase db) async {
      await db.writeTransaction((tx) async {
        await tx.execute(
            'CREATE TABLE test_data(id INTEGER PRIMARY KEY AUTOINCREMENT, description TEXT)');
      });
    }

    test('Basic Setup', () async {
      final db = await setupCipherDatabase(key: 'testkey', path: path);
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
  });
}

// For some reason, future.ignore() doesn't actually ignore errors in these tests.
void ignore(Future future) {
  future.then((_) {}, onError: (_) {});
}
