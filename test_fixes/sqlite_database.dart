import 'package:sqlite_async/src/sqlite_database.dart';

var db = SqliteDatabase(path: 'test.db');

void main() async {
  db.writeTransaction((tx) async {
    await tx.execute('select 1');
  });

  db.readTransaction((tx) async {
    await tx.getAll('select 1');
  });
}
