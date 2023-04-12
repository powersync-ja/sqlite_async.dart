import 'dart:math';

import 'package:sqlite_async/sqlite_async.dart';

/// Migrations to setup the database.
///
/// For more options, see `migration_example.dart`.
final migrations = SqliteMigrations()
  ..add(SqliteMigration(1, (tx) async {
    await tx.execute(
        'CREATE TABLE test_data(id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT)');
  }));

void main() async {
  // Open the database
  final db = SqliteDatabase(path: 'test.db');
  // Run migrations - do this before any other queries
  await migrations.migrate(db);

  // Use execute() or executeBatch() for INSERT/UPDATE/DELETE statements
  await db.executeBatch('INSERT INTO test_data(data) values(?)', [
    ['Test1'],
    ['Test2']
  ]);

  List<Future> futures = [];
  for (var i = 0; i < 1000; i++) {
    // Combine multiple statements into a single write transaction for:
    // 1. Atomic persistence (all updates are either applied or rolled back).
    // 2. Improved throughput.
    var future = db.writeTransaction((tx) async {
      await tx.execute('INSERT INTO test_data(data) values(?)', ['Test3']);
      await Future.delayed(Duration(milliseconds: Random().nextInt(2)));
      await tx.execute('INSERT INTO test_data(data) values(?)', ['Test4']);
    });
    futures.add(future);
  }
  await Future.wait(futures);

  // Use getAll(), get() or getOptional() for SELECT statements
  var results = await db.getAll('SELECT * FROM test_data');
  print('Results: $results');

  // Close database to release resources
  await db.close();
}
