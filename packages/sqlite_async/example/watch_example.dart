import 'package:sqlite_async/sqlite_async.dart';

final migrations = SqliteMigrations()
  ..add(SqliteMigration(1, (tx) async {
    await tx.execute(
        'CREATE TABLE test_data(id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT)');
  }));

void main() async {
  final db = SqliteDatabase(path: 'test.db');
  await migrations.migrate(db);

  // This query is re-executed every time test_data changes.
  var stream1 = db.watch('SELECT data FROM test_data');
  var subscription1 = stream1.listen((results) {
    print(results);
  });

  // Use this to get notifications of changes on one or more tables.
  var stream2 = db.onChange(['test_data']);
  var subscription2 = stream2.listen((changes) {
    print(changes);
  });

  // This achieves the same as db.watch(), but:
  // 1. Explicitly specifies the tables to watch for changes.
  // 2. May run any number of queries when a change is triggered.
  var stream3 = db.onChange(['test_data']).asyncMap((event) async {
    return db.getAll('SELECT count() as count FROM test_data');
  });
  var subscription3 = stream3.listen((results) {
    print(results);
  });

  for (var i = 0; i < 5; i++) {
    await db.execute('INSERT INTO test_data(data) values(?)', ['Test $i']);
    await Future.delayed(Duration(milliseconds: 100));
  }

  subscription1.cancel();
  subscription2.cancel();
  subscription3.cancel();
  await db.close();
}
