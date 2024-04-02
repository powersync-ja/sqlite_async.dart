import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test_api/src/backend/invoker.dart';

const defaultSqlitePath = 'libsqlite3.so.0';
// const defaultSqlitePath = './sqlite-autoconf-3410100/.libs/libsqlite3.so.0';

class TestSqliteOpenFactory extends DefaultSqliteOpenFactory {
  String sqlitePath;

  TestSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions,
      this.sqlitePath = defaultSqlitePath});

  @override
  sqlite.Database open(SqliteOpenOptions options) {
    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, () {
      return DynamicLibrary.open(sqlitePath);
    });
    final db = super.open(options);

    db.createFunction(
      functionName: 'test_sleep',
      argumentCount: const sqlite.AllowedArgumentCount(1),
      function: (args) {
        final millis = args[0] as int;
        sleep(Duration(milliseconds: millis));
        return millis;
      },
    );

    db.createFunction(
      functionName: 'test_connection_name',
      argumentCount: const sqlite.AllowedArgumentCount(0),
      function: (args) {
        return Isolate.current.debugName;
      },
    );

    return db;
  }
}

SqliteOpenFactory testFactory({String? path}) {
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
