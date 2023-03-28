import 'dart:ffi';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart' as sqlite;

const defaultSqlitePath = 'libsqlite3.so.0';

/// Custom factory to configure how the database is opened in each Isolate.
class TestOpenFactory extends DefaultSqliteOpenFactory {
  String sqlitePath;

  TestOpenFactory(
      {required super.path,
      super.sqliteOptions,
      this.sqlitePath = defaultSqlitePath});

  @override
  sqlite.Database open(SqliteOpenOptions options) {
    // For details, see:
    // https://pub.dev/packages/sqlite3#manually-providing-sqlite3-libraries
    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.linux, () {
      return DynamicLibrary.open(sqlitePath);
    });
    final db = super.open(options);

    return db;
  }
}

void main() async {
  final db = SqliteDatabase.withFactory(TestOpenFactory(path: 'test.db'));
  final version = await db.get('SELECT sqlite_version() as version');
  print("Version: ${version['version']}");
  await db.close();
}
