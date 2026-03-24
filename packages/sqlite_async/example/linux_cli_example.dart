import 'package:sqlite_async/sqlite_async.dart';

void main() async {
  final db = SqliteDatabase(path: 'test.db');
  final version = await db.get('SELECT sqlite_version() as version');
  print("Version: ${version['version']}");
  await db.close();
}
