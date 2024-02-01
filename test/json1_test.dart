import 'dart:convert';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

class TestUser {
  int? id;
  String? name;
  String? email;

  TestUser({this.id, this.name, this.email});

  factory TestUser.fromMap(Map<String, dynamic> data) {
    return TestUser(id: data['id'], name: data['name'], email: data['email']);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'email': email};
  }
}

void main() {
  group('json1 Tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    tearDown(() async {
      await testUtils.cleanDb(path: path);
    });

    createTables(AbstractSqliteDatabase db) async {
      await db.writeTransaction((tx) async {
        await tx.execute(
            'CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT)');
      });
    }

    test('Inserts', () async {
      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);
      var users1 = [
        TestUser(name: 'Bob', email: 'bob@example.org'),
        TestUser(name: 'Alice', email: 'alice@example.org')
      ];
      var users2 = [
        TestUser(name: 'Charlie', email: 'charlie@example.org'),
        TestUser(name: 'Dan', email: 'dan@example.org')
      ];

      print(jsonEncode(users1));
      var ids1 = await db.execute(
          "INSERT INTO users(name, email) SELECT e.value ->> 'name', e.value ->> 'email' FROM json_each(?) e RETURNING id",
          [jsonEncode(users1)]);

      var ids2 = await db.execute(
          "INSERT INTO users(name, email) ${selectJsonColumns([
                'name',
                'email'
              ])} RETURNING id",
          [jsonEncode(users2)]);

      var ids = [
        for (var row in ids1) row,
        for (var row in ids2) row,
      ];

      var results = [
        for (var row in await db.getAll(
            "SELECT id, name, email FROM users WHERE id IN (${selectJsonColumns([
                  'id'
                ])}) ORDER BY name",
            [jsonEncode(ids)]))
          TestUser.fromMap(row)
      ];

      expect(results.map((u) => u.name),
          equals(['Alice', 'Bob', 'Charlie', 'Dan']));
    });
  });
}

// For some reason, future.ignore() doesn't actually ignore errors in these tests.
void ignore(Future future) {
  future.then((_) {}, onError: (_) {});
}
