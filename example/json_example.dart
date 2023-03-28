import 'package:sqlite_async/sqlite_async.dart';

// This example shows using a custom class and SQLite's JSON1 functionality,
// to efficiently map between custom data objects and SQLite.
// This is especially useful for bulk INSERT, UPDATE or DELETE statements,

class User {
  int? id;
  String name;
  String email;

  User({this.id, required this.name, required this.email});

  /// For mapping query results.
  factory User.fromMap(Map<String, dynamic> data) {
    return User(id: data['id'], name: data['name'], email: data['email']);
  }

  /// JSON representation, used for query parameters.
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'email': email};
  }

  @override
  String toString() {
    return 'User<id: $id, name: $name, email: $email>';
  }

  /// Helper to use in queries.
  /// This produces an equivalent to:
  ///
  /// ```sql
  /// SELECT
  ///       json_each.value ->> 'id' as id,
  ///       json_each.value ->> 'name' as name,
  ///       json_each.value ->> 'email' as email
  /// FROM json_each(?)
  static final selectJsonData = selectJsonColumns(['id', 'name', 'email']);
}

final migrations = SqliteMigrations()
  ..add(SqliteMigration(1, (tx) async {
    await tx.execute(
        'CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT)');
  }));

void main() async {
  final db = SqliteDatabase(path: 'users.db');
  await migrations.migrate(db);

  var users = [
    User(name: 'Bob', email: 'bob@example.org'),
    User(name: 'Alice', email: 'alice@example.org')
  ];

  // Insert data and get resulting ids.
  // Here, the list of users is automatically encoded as JSON using [User.toJson].
  // "RETURNING id" is used to get the auto-generated ids.
  var idRows = await db.execute('''
INSERT INTO users(name, email)
SELECT name, email FROM (${User.selectJsonData('?')})
RETURNING id''', [users]);
  var ids = idRows.map((row) => row['id']).toList();

  // Alternatively, using json1 functions directly.
  var idRows2 = await db.execute('''
INSERT INTO users(name, email)
SELECT e.value ->> 'name', e.value ->> 'email' FROM json_each(?) e
RETURNING id''', [users]);

  // Select using "WHERE id IN ...".
  var queriedUsers = (await db.getAll(
          "SELECT id, name, email FROM users WHERE id IN (SELECT json_each.value FROM json_each(?)) ORDER BY name",
          [ids]))
      .map(User.fromMap)
      .toList();

  print(queriedUsers);

  // Bulk update using UPDATE FROM.
  await db.execute('''
UPDATE users
  SET name = args.name, email = args.email
FROM (${User.selectJsonData('?')}) as args
  WHERE users.id = args.id''', [queriedUsers]);

  // Bulk delete using "WHERE id IN ...".
  await db.execute('''
DELETE FROM users WHERE id IN (SELECT json_each.value FROM json_each(?))''',
      [queriedUsers.map((u) => u.id).toList()]);

  await db.close();
}
