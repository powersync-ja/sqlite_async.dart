import 'package:drift/drift.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import './utils/test_utils.dart';
import 'generated/database.dart';

void main() {
  group('Generated DB tests', () {
    late String path;
    late SqliteDatabase db;
    late TodoDatabase dbu;

    createTables(SqliteDatabase db) async {
      await db.writeTransaction((tx) async {
        await tx.execute(
            'CREATE TABLE todos(id INTEGER PRIMARY KEY AUTOINCREMENT, description TEXT)');
      });
    }

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);

      db = await setupDatabase(path: path);
      dbu = TodoDatabase(db);
      await createTables(db);
    });

    tearDown(() async {
      await dbu.close();
      await db.close();

      await cleanDb(path: path);
    });

    test('INSERT/SELECT', () async {
      var insertRowId = await dbu
          .into(dbu.todoItems)
          .insert(TodoItemsCompanion.insert(description: 'Test 1'));
      expect(insertRowId, greaterThanOrEqualTo(1));

      final result = await dbu.select(dbu.todoItems).getSingle();
      expect(result.description, equals('Test 1'));
    });

    test('watch', () async {
      var stream = dbu.select(dbu.todoItems).watch();
      var resultsPromise =
          stream.distinct().skipWhile((e) => e.isEmpty).take(3).toList();

      await dbu.into(dbu.todoItems).insert(
          TodoItemsCompanion.insert(id: Value(1), description: 'Test 1'));

      await Future.delayed(Duration(milliseconds: 100));
      await (dbu.update(dbu.todoItems))
          .write(TodoItemsCompanion(description: Value('Test 1B')));

      await Future.delayed(Duration(milliseconds: 100));
      await (dbu.delete(dbu.todoItems).go());

      var results = await resultsPromise.timeout(Duration(milliseconds: 500));
      expect(
          results,
          equals([
            [TodoItem(id: 1, description: 'Test 1')],
            [TodoItem(id: 1, description: 'Test 1B')],
            []
          ]));
    });

    test('watch with external updates', () async {
      var stream = dbu.select(dbu.todoItems).watch();
      var resultsPromise =
          stream.distinct().skipWhile((e) => e.isEmpty).take(3).toList();

      await db.execute(
          'INSERT INTO todos(id, description) VALUES(?, ?)', [1, 'Test 1']);
      await Future.delayed(Duration(milliseconds: 100));
      await db.execute(
          'UPDATE todos SET description = ? WHERE id = ?', ['Test 1B', 1]);
      await Future.delayed(Duration(milliseconds: 100));
      await db.execute('DELETE FROM todos WHERE id = 1');

      var results = await resultsPromise.timeout(Duration(milliseconds: 500));
      expect(
          results,
          equals([
            [TodoItem(id: 1, description: 'Test 1')],
            [TodoItem(id: 1, description: 'Test 1B')],
            []
          ]));
    });
  });
}
