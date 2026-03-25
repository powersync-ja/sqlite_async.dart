import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test_api/src/backend/invoker.dart';

class TestSqliteOpenFactory extends DefaultSqliteOpenFactory {
  TestSqliteOpenFactory({
    required super.path,
    super.sqliteOptions,
  });

  @override
  CommonDatabase open(SqliteOpenOptions options) {
    final db = super.open(options);

    return db;
  }
}

DefaultSqliteOpenFactory testFactory({String? path}) {
  return TestSqliteOpenFactory(path: path ?? dbPath());
}

Future<SqliteDatabase> setupDatabase({String? path}) async {
  final db = SqliteDatabase.withFactory(testFactory(path: path));
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

List<String> findSqliteLibraries() {
  var glob = Glob('sqlite-*/.libs/libsqlite3.so');
  List<String> sqlites = [
    'libsqlite3.so.0',
    for (var sqlite in glob.listSync()) sqlite.path
  ];
  return sqlites;
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
