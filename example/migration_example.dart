import 'package:sqlite_async/sqlite_async.dart';

final migrations = SqliteMigrations()
  ..add(SqliteMigration(1, (tx) async {
    await tx.execute(
        'CREATE TABLE test_data(id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT)');
  }))
  ..add(SqliteMigration(2, (tx) async {
    await tx.execute('ALTER TABLE test_data ADD COLUMN comment TEXT');
  },
      // Optional: Add a down migration that will execute when users install an older application version.
      // This is typically not required for Android or iOS where users cannot install older versions,
      // but may be useful on other platforms or during development.
      downMigration: SqliteDownMigration(toVersion: 1)
        ..add('ALTER TABLE test_data DROP COLUMN comment')))
  // Optional: Provide a function to initialize the database from scratch,
  // avoiding the need to run through incremental migrations for new databases.
  ..createDatabase = SqliteMigration(
    2,
    (tx) async {
      await tx.execute(
          'CREATE TABLE test_data(id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT, comment TEXT)');
    },
  );

void main() async {
  final db = SqliteDatabase(path: 'test.db');
  // Make sure to run migrations before any other functions access the database.
  await migrations.migrate(db);
  await db.close();
}
