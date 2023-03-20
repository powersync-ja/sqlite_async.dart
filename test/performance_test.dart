import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import 'util.dart';

void main() {
  setupLogger();

  createTables(SqliteDatabase db) async {
    await db.writeTransaction((tx) async {
      await tx.execute(
          'CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT)');
    });
  }

  group('Performance Tests', () {
    late String path;

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);
    });

    tearDown(() async {
      await cleanDb(path: path);
    });

    // Manual tests
    test('Insert Performance 1 - direct', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);

      final timer = Stopwatch()..start();

      for (var i = 0; i < 1000; i++) {
        await db.execute('INSERT INTO customers(name, email) VALUES(?, ?)',
            ['Test User', 'user@example.org']);
      }
      print("Completed sequential inserts in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });

    test('Insert Performance 2 - writeTransaction', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);

      final timer = Stopwatch()..start();

      await db.writeTransaction((tx) async {
        for (var i = 0; i < 1000; i++) {
          await tx.execute('INSERT INTO customers(name, email) VALUES(?, ?)',
              ['Test User', 'user@example.org']);
        }
      });
      print("Completed transaction inserts in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });

    test('Insert Performance 3a - computeWithDatabase', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);
      final timer = Stopwatch()..start();

      await db.computeWithDatabase((db) async {
        for (var i = 0; i < 1000; i++) {
          db.execute('INSERT INTO customers(name, email) VALUES(?, ?)',
              ['Test User', 'user@example.org']);
        }
      });

      print("Completed synchronous inserts in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });

    test('Insert Performance 3b - prepared statement', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);

      final timer = Stopwatch()..start();

      await db.computeWithDatabase((db) async {
        var stmt =
            db.prepare('INSERT INTO customers(name, email) VALUES(?, ?)');
        try {
          for (var i = 0; i < 1000; i++) {
            stmt.execute(['Test User', 'user@example.org']);
          }
        } finally {
          stmt.dispose();
        }
      });

      print("Completed synchronous inserts prepared in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });

    test('Insert Performance 4 - pipelined', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);
      final timer = Stopwatch()..start();

      await db.writeTransaction((tx) async {
        List<Future> futures = [];
        for (var i = 0; i < 1000; i++) {
          var future = tx.execute(
              'INSERT INTO customers(name, email) VALUES(?, ?)',
              ['Test User', 'user@example.org']);
          futures.add(future);
        }
        await Future.wait(futures);
      });
      print("Completed pipelined inserts in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });

    test('Insert Performance 5 - executeBatch', () async {
      final db = await setupDatabase(path: path);
      await createTables(db);
      final timer = Stopwatch()..start();

      var parameters =
          List.generate(1000, (index) => ['Test user', 'user@example.org']);
      await db.executeBatch(
          'INSERT INTO customers(name, email) VALUES(?, ?)', parameters);
      print("Completed executeBatch in ${timer.elapsed}");
      expect(await db.get('SELECT count(*) as count FROM customers'),
          equals({'count': 1000}));
    });
  });
}
