import 'dart:async';
import 'dart:math';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/src/utils/shared_utils.dart';
import 'package:test/test.dart';

import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

createTables(SqliteDatabase db) async {
  await db.writeTransaction((tx) async {
    await tx.execute(
        'CREATE TABLE assets(id INTEGER PRIMARY KEY AUTOINCREMENT, make TEXT, customer_id INTEGER)');
    await tx.execute('CREATE INDEX assets_customer ON assets(customer_id)');
    await tx.execute(
        'CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)');
    await tx.execute(
        'CREATE TABLE other_customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)');
    await tx.execute('CREATE VIEW assets_alias AS SELECT * FROM assets');
  });
}

// Web and native have different requirements for `sqlitePaths`.
void generateSourceTableTests(List<String> sqlitePaths,
    Future<SqliteDatabase> Function(String sqlitePath) generateDB) {
  for (var sqlite in sqlitePaths) {
    test('getSourceTables - $sqlite', () async {
      final db = await generateDB(sqlite);
      await createTables(db);

      var versionRow = await db.get('SELECT sqlite_version() as version');
      print('Testing SQLite ${versionRow['version']} - $sqlite');

      final tables = await getSourceTables(db,
          'SELECT * FROM assets INNER JOIN customers ON assets.customer_id = customers.id');
      expect(tables, equals({'assets', 'customers'}));

      final tables2 = await getSourceTables(db,
          'SELECT count() FROM assets INNER JOIN "other_customers" AS oc ON assets.customer_id = oc.id AND assets.make = oc.name');
      expect(tables2, equals({'assets', 'other_customers'}));

      final tables3 = await getSourceTables(db, 'SELECT count() FROM assets');
      expect(tables3, equals({'assets'}));

      final tables4 =
          await getSourceTables(db, 'SELECT count() FROM assets_alias');
      expect(tables4, equals({'assets'}));

      final tables5 =
          await getSourceTables(db, 'SELECT sqlite_version() as version');
      expect(tables5, equals(<String>{}));
    });
  }
}

void main() {
  // Shared tests for watch
  group('Query Watch Tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    test('watch', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);

      const baseTime = 20;

      const throttleDuration = Duration(milliseconds: baseTime);

      final stream = db.watch(
          'SELECT count() AS count FROM assets INNER JOIN customers ON customers.id = assets.customer_id',
          throttle: throttleDuration);

      final rows = await db.execute(
          'INSERT INTO customers(name) VALUES (?) RETURNING id',
          ['a customer']);
      final id = rows[0]['id'];

      var done = false;
      inserts() async {
        while (!done) {
          await db.execute(
              'INSERT INTO assets(make, customer_id) VALUES (?, ?)',
              ['test', id]);
          await Future.delayed(
              Duration(milliseconds: Random().nextInt(baseTime * 2)));
        }
      }

      const numberOfQueries = 10;

      inserts();
      try {
        List<DateTime> times = [];
        final results = await stream.take(numberOfQueries).map((e) {
          times.add(DateTime.now());
          return e;
        }).toList();

        var lastCount = 0;
        for (var r in results) {
          final count = r.first['count'];
          // This is not strictly incrementing, since we can't guarantee the
          // exact order between reads and writes.
          // We can guarantee that there will always be a read after the last write,
          // but the previous read may have been after the same write in some cases.
          expect(count, greaterThanOrEqualTo(lastCount));
          lastCount = count;
        }

        // The number of read queries must not be greater than the number of writes overall.
        expect(numberOfQueries, lessThanOrEqualTo(results.last.first['count']));

        DateTime? lastTime;
        for (var r in times) {
          if (lastTime != null) {
            var diff = r.difference(lastTime);
            expect(diff, greaterThanOrEqualTo(throttleDuration));
          }
          lastTime = r;
        }
      } finally {
        done = true;
      }
    });

    test('onChange', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);

      const baseTime = 20;

      const throttleDuration = Duration(milliseconds: baseTime);

      var done = false;
      inserts() async {
        while (!done) {
          await db.execute('INSERT INTO assets(make) VALUES (?)', ['test']);
          await Future.delayed(
              Duration(milliseconds: Random().nextInt(baseTime)));
        }
      }

      inserts();

      final stream = db.onChange({'assets', 'customers'},
          throttle: throttleDuration).asyncMap((event) async {
        // This is where queries would typically be executed
        return event;
      });

      var events = await stream.take(3).toList();
      done = true;

      expect(
          events,
          equals([
            UpdateNotification.empty(),
            UpdateNotification.single('assets'),
            UpdateNotification.single('assets')
          ]));
    });

    test('single onChange', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);

      const baseTime = 20;

      const throttleDuration = Duration(milliseconds: baseTime);

      final stream = db.onChange({'assets', 'customers'},
          throttle: throttleDuration,
          triggerImmediately: false).asyncMap((event) async {
        // This is where queries would typically be executed
        return event;
      });

      var eventsFuture = stream.take(1).toList();
      await db.execute('INSERT INTO assets(make) VALUES (?)', ['test']);
      var events = await eventsFuture;

      expect(events, equals([UpdateNotification.single('assets')]));
    });

    test('watch with parameters', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);

      const baseTime = 20;

      const throttleDuration = Duration(milliseconds: baseTime);

      final rows = await db.execute(
          'INSERT INTO customers(name) VALUES (?) RETURNING id',
          ['a customer']);
      final id = rows[0]['id'];

      final stream = db.watch(
          'SELECT count() AS count FROM assets WHERE customer_id = ?',
          parameters: [id],
          throttle: throttleDuration);

      var done = false;
      inserts() async {
        while (!done) {
          await db.execute(
              'INSERT INTO assets(make, customer_id) VALUES (?, ?)',
              ['test', id]);
          await Future.delayed(
              Duration(milliseconds: Random().nextInt(baseTime * 2)));
        }
      }

      const numberOfQueries = 10;

      inserts();
      try {
        List<DateTime> times = [];
        final results = await stream.take(numberOfQueries).map((e) {
          times.add(DateTime.now());
          return e;
        }).toList();

        var lastCount = 0;
        for (var r in results) {
          final count = r.first['count'];
          // This is not strictly incrementing, since we can't guarantee the
          // exact order between reads and writes.
          // We can guarantee that there will always be a read after the last write,
          // but the previous read may have been after the same write in some cases.
          expect(count, greaterThanOrEqualTo(lastCount));
          lastCount = count;
        }

        // The number of read queries must not be greater than the number of writes overall.
        expect(numberOfQueries, lessThanOrEqualTo(results.last.first['count']));

        DateTime? lastTime;
        for (var r in times) {
          if (lastTime != null) {
            var diff = r.difference(lastTime);
            expect(diff, greaterThanOrEqualTo(throttleDuration));
          }
          lastTime = r;
        }
      } finally {
        done = true;
      }
    });
  });
}
