import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import 'util.dart';

void main() {
  setupLogger();

  group('Basic Tests', () {
    late String path;

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);
    });

    tearDown(() async {
      await cleanDb(path: path);
    });

    test('Basic Migrations', () async {
      final db = await setupDatabase(path: path);
      final migrations = SqliteMigrations();
      migrations.add(SqliteMigration(1, (tx) async {
        await tx.execute(
            'CREATE TABLE test1(id INTEGER PRIMARY KEY AUTOINCREMENT, description TEXT)');
        await tx.execute(
            'INSERT INTO test1(description) VALUES(?)', ['Migration1']);
      }));
      expect(await migrations.getCurrentVersion(db), equals(0));
      await migrations.migrate(db);
      expect(await migrations.getCurrentVersion(db), equals(1));
      expect(
          await db.getAll('SELECT description FROM test1 ORDER BY id'),
          equals([
            {'description': 'Migration1'}
          ]));

      migrations.add(SqliteMigration(2, (tx) async {
        await tx.execute(
            'INSERT INTO test1(description) VALUES(?)', ['Migration2']);
      }));

      await migrations.migrate(db);
      expect(await migrations.getCurrentVersion(db), equals(2));

      expect(
          await db.getAll('SELECT description FROM test1 ORDER BY id'),
          equals([
            {'description': 'Migration1'},
            {'description': 'Migration2'}
          ]));
    });

    test('Migration with createDatabase', () async {
      final db = await setupDatabase(path: path);
      final migrations = SqliteMigrations();
      migrations.add(SqliteMigration(1, (tx) async {
        await tx.execute(
            'CREATE TABLE test1(id INTEGER PRIMARY KEY AUTOINCREMENT, description TEXT) -- migration1');
        await tx.execute(
            'INSERT INTO test1(description) VALUES(?)', ['Migration1']);
      }));

      migrations.add(SqliteMigration(2, (tx) async {
        await tx.execute(
            'INSERT INTO test1(description) VALUES(?)', ['Migration2']);
      }));

      migrations.createDatabase = SqliteMigration(2, (tx) async {
        await tx.execute(
            'CREATE TABLE test1(id INTEGER PRIMARY KEY AUTOINCREMENT, description TEXT) -- createDatabase');
        await tx
            .execute('INSERT INTO test1(description) VALUES(?)', ['Create']);
      });

      expect(await migrations.getCurrentVersion(db), equals(0));
      await migrations.migrate(db);
      expect(await migrations.getCurrentVersion(db), equals(2));
      expect(
          await db.getAll('SELECT description FROM test1'),
          equals([
            {'description': 'Create'}
          ]));
    });

    test('Migration with down migrations', () async {
      final db = await setupDatabase(path: path);
      final migrations = SqliteMigrations();
      migrations.add(SqliteMigration(1, (tx) async {
        await tx.execute(
            'CREATE TABLE test1(id INTEGER PRIMARY KEY AUTOINCREMENT, description TEXT) -- migration1');
        await tx.execute(
            'INSERT INTO test1(description) VALUES(?)', ['Migration1']);
      },
          downMigration: SqliteDownMigration(toVersion: 0)
            ..add('DROP TABLE test1')));

      migrations.add(SqliteMigration(2, (tx) async {
        await tx.execute(
            'INSERT INTO test1(description) VALUES(?)', ['Migration2']);
      },
          downMigration: SqliteDownMigration(toVersion: 1)
            ..add('DELETE FROM test1 WHERE description = ?', ['Migration2'])));

      expect(await migrations.getCurrentVersion(db), equals(0));
      await migrations.migrate(db);
      expect(await migrations.getCurrentVersion(db), equals(2));

      expect(
          await db.getAll('SELECT description FROM test1 ORDER BY id'),
          equals([
            {'description': 'Migration1'},
            {'description': 'Migration2'}
          ]));

      migrations.migrations.removeLast();

      await migrations.migrate(db);
      expect(await migrations.getCurrentVersion(db), equals(1));

      expect(
          await db.getAll('SELECT description FROM test1 ORDER BY id'),
          equals([
            {'description': 'Migration1'}
          ]));

      migrations.migrations.removeLast();
      await migrations.migrate(db);
      expect(await migrations.getCurrentVersion(db), equals(0));

      expect(
          await db.getAll(
              "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
              ['test1']),
          equals([]));
    });

    test('Migration with double down migrations', () async {
      final db = await setupDatabase(path: path);
      final migrations = SqliteMigrations();
      migrations.add(SqliteMigration(1, (tx) async {
        await tx.execute(
            'CREATE TABLE test1(id INTEGER PRIMARY KEY AUTOINCREMENT, description TEXT) -- migration1');
        await tx.execute(
            'INSERT INTO test1(description) VALUES(?)', ['Migration1']);
      }));

      migrations.add(SqliteMigration(2, (tx) async {
        await tx.execute(
            'INSERT INTO test1(description) VALUES(?)', ['Migration2']);
      },
          downMigration: SqliteDownMigration(toVersion: 0)
            ..add('DROP TABLE test1')));

      expect(await migrations.getCurrentVersion(db), equals(0));
      await migrations.migrate(db);
      expect(await migrations.getCurrentVersion(db), equals(2));

      expect(
          await db.getAll('SELECT description FROM test1 ORDER BY id'),
          equals([
            {'description': 'Migration1'},
            {'description': 'Migration2'}
          ]));

      migrations.migrations.removeLast();

      // Downgrades to 0, then back up to 1
      await migrations.migrate(db);
      expect(await migrations.getCurrentVersion(db), equals(1));

      expect(
          await db.getAll('SELECT description FROM test1 ORDER BY id'),
          equals([
            {'description': 'Migration1'}
          ]));
    });
  });
}
