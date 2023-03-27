import 'package:sqlite_async/sqlite_async.dart';

final migrations = SqliteMigrations()
  ..add(SqliteMigration(1, (tx) async {
    await tx.execute(
        'CREATE TABLE test_data(id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT)');
  }));

void main() async {
  final db = SqliteDatabase(path: 'test.db');
  await migrations.migrate(db);

  // Use execute() or executeBatch() for INSERT/UPDATE/DELETE statements
  await db.executeBatch('INSERT INTO test_data(data) values(?)', [
    ['Test1'],
    ['Test2']
  ]);

  // Use getAll(), get() or getOptional() for SELECT statements
  var results = await db.getAll('SELECT * FROM test_data');
  print('Results: $results');

  // Combine multiple statements into a single write transaction for:
  // 1. Atomic persistence (all updates are either applied or rolled back).
  // 2. Improved throughput.
  await db.writeTransaction((tx) async {
    await db.execute('INSERT INTO test_data(data) values(?)', ['Test3']);
    await db.execute('INSERT INTO test_data(data) values(?)', ['Test4']);
  });

  await db.close();
}