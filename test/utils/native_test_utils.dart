import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite3/open.dart' as sqlite_open;

import 'abstract_test_utils.dart';

const defaultSqlitePath = 'libsqlite3.so.0';

class TestSqliteOpenFactory extends TestDefaultSqliteOpenFactory {
  TestSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions,
      super.sqlitePath = defaultSqlitePath});

  @override
  FutureOr<CommonDatabase> open(SqliteOpenOptions options) async {
    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, () {
      return DynamicLibrary.open(sqlitePath);
    });
    final db = await super.open(options);

    db.createFunction(
      functionName: 'test_sleep',
      argumentCount: const AllowedArgumentCount(1),
      function: (args) {
        final millis = args[0] as int;
        sleep(Duration(milliseconds: millis));
        return millis;
      },
    );

    db.createFunction(
      functionName: 'test_connection_name',
      argumentCount: const AllowedArgumentCount(0),
      function: (args) {
        return Isolate.current.debugName;
      },
    );

    return db;
  }
}

class TestUtils extends AbstractTestUtils {
  @override
  Future<void> init() async {}

  @override
  String dbPath() {
    Directory("test-db").createSync(recursive: false);
    return super.dbPath();
  }

  @override
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

  @override
  List<String> findSqliteLibraries() {
    var glob = Glob('sqlite-*/.libs/libsqlite3.so');
    List<String> sqlites = [
      'libsqlite3.so.0',
      for (var sqlite in glob.listSync()) sqlite.path
    ];
    return sqlites;
  }

  @override
  TestDefaultSqliteOpenFactory testFactory(
      {String? path,
      String sqlitePath = defaultSqlitePath,
      SqliteOptions options = const SqliteOptions.defaults()}) {
    return TestSqliteOpenFactory(
        path: path ?? dbPath(), sqlitePath: sqlitePath, sqliteOptions: options);
  }
}
