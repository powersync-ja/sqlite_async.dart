import 'dart:async';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:sqlite_async/sqlite3.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'abstract_test_utils.dart';

const defaultSqlitePath = 'libsqlite3.so.0';

class TestSqliteOpenFactory extends TestDefaultSqliteOpenFactory {
  TestSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions,
      super.sqlitePath = defaultSqlitePath,
      initStatements});

  @override
  Future<CommonDatabase> openDatabaseForSingleConnection() async {
    return sqlite3.openInMemory();
  }
}

class TestUtils extends AbstractTestUtils {
  @override
  String dbPath() {
    return d.path('test.db');
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
  Future<TestDefaultSqliteOpenFactory> testFactory(
      {String? path,
      String sqlitePath = defaultSqlitePath,
      List<String> initStatements = const [],
      SqliteOptions options = const SqliteOptions.defaults()}) async {
    return TestSqliteOpenFactory(
        path: path ?? dbPath(),
        sqlitePath: sqlitePath,
        sqliteOptions: options,
        initStatements: initStatements);
  }
}
