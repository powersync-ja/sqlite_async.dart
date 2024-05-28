@TestOn('!browser')
import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:sqlite3/common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import '../utils/test_utils_impl.dart';
import '../watch_test.dart';

final testUtils = TestUtils();

void main() {
  group('Query Watch Tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    generateSourceTableTests(testUtils.findSqliteLibraries(),
        (String sqlitePath) async {
      final db =
          SqliteDatabase.withFactory(await testUtils.testFactory(path: path));
      await db.initialize();
      return db;
    });

    test('watch in isolate', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);

      const baseTime = 20;

      const throttleDuration = Duration(milliseconds: baseTime);

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

      final factory = db.isolateConnectionFactory();

      var l = await inIsolateWatch(factory, numberOfQueries, throttleDuration);

      var results = l[0] as List<ResultSet>;
      var times = l[1] as List<DateTime>;
      done = true;

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
    });
  });
}

Future<List<Object>> inIsolateWatch(IsolateConnectionFactory factory,
    int numberOfQueries, Duration throttleDuration) async {
  return await Isolate.run(() async {
    final db = factory.open();

    final stream = db.watch(
        'SELECT count() AS count FROM assets INNER JOIN customers ON customers.id = assets.customer_id',
        throttle: throttleDuration);
    List<DateTime> times = [];
    final results = await stream.take(numberOfQueries).map((e) {
      times.add(DateTime.now());
      return e;
    }).toList();

    db.close();
    return [results, times];
  });
}
