@TestOn('!browser')
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import './utils/test_utils.dart';
import 'generated/database.dart';

void main() {
  group('Migration tests', () {
    late String path;
    late SqliteDatabase db;
    late TodoDatabase dbu;

    setUp(() async {
      path = dbPath();
      await cleanDb(path: path);

      db = await setupDatabase(path: path);
      dbu = TodosMigrationDatabase(db);
    });

    tearDown(() async {
      await dbu.close();
      await db.close();

      await cleanDb(path: path);
    });

    test('INSERT/SELECT', () async {
      // This will fail if the migration didn't run
      var insertRowId = await dbu
          .into(dbu.todoItems)
          .insert(TodoItemsCompanion.insert(description: 'Test 1'));
      expect(insertRowId, greaterThanOrEqualTo(1));

      final result = await dbu.select(dbu.todoItems).getSingle();
      expect(result.description, equals('Test 1'));
    });
  });
}
