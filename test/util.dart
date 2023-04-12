import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test_api/src/backend/invoker.dart';

// const defaultSqlitePath = 'libsqlite3.so.0';
const defaultSqlitePath = '/usr/lib/x86_64-linux-gnu/libsqlcipher.so.0';
// const defaultSqlitePath = './sqlite-autoconf-3410100/.libs/libsqlite3.so.0';

class SqlcipherOpenFactory extends DefaultSqliteOpenFactory {
  String? key;

  SqlcipherOpenFactory({required super.path, super.sqliteOptions, this.key});

  @override
  sqlite.Database open(SqliteOpenOptions options) {
    final db = super.open(options);

    if (key != null) {
      // Make sure that SQLCipher is used, not plain SQLite.
      final versionRows = db.select('PRAGMA cipher_version');
      if (versionRows.isEmpty) {
        throw AssertionError(
            'SQLite library is plain SQLite; SQLCipher expected.');
      }
    }
    return db;
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    final defaultStatements = super.pragmaStatements(options);
    if (key != null) {
      return [
        // Run this as the first statement
        "PRAGMA KEY = '$key'",
        for (var statement in defaultStatements) statement
      ];
    } else {
      return defaultStatements;
    }
  }
}

SqliteOpenFactory testFactory({String? path, String? key}) {
  return SqlcipherOpenFactory(path: path ?? dbPath(), key: key);
}

Future<SqliteDatabase> setupDatabase({String? path}) async {
  final db = SqliteDatabase.withFactory(testFactory(path: path));
  await db.initialize();
  return db;
}

Future<SqliteDatabase> setupCipherDatabase({
  required String key,
  String? path,
}) async {
  final db = SqliteDatabase.withFactory(testFactory(path: path, key: key));
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
