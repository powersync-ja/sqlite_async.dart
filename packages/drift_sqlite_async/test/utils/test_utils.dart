import 'dart:io';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:test_api/src/backend/invoker.dart';

Future<SqliteDatabase> setupDatabase({String? path}) async {
  final db =
      SqliteDatabase.withFactory(SqliteOpenFactory(path: path ?? dbPath()));
  await db.initialize();
  return db;
}

Future<void> cleanDb({required String path}) async {
  try {
    await File(path).delete();
  } on PathNotFoundException {
    // Not an issue
  }
  try {
    await File("$path-shm").delete();
  } on PathNotFoundException {
    // Not an issue
  }
  try {
    await File("$path-wal").delete();
  } on PathNotFoundException {
    // Not an issue
  }
}

String dbPath() {
  final test = Invoker.current!.liveTest;
  var testName = test.test.name;
  var testShortName =
      testName.replaceAll(RegExp(r'[\s\./]'), '_').toLowerCase();
  var dbName = "test-db/$testShortName.db";
  Directory("test-db").createSync(recursive: false);
  return dbName;
}
