import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart' as sqlite;

class TestOpenFactory extends DefaultSqliteOpenFactory {
  TestOpenFactory({required super.path, super.sqliteOptions});

  @override
  sqlite.Database open(SqliteOpenOptions options) {
    final db = super.open(options);

    db.createFunction(
      functionName: 'sleep',
      argumentCount: const sqlite.AllowedArgumentCount(1),
      function: (args) {
        final millis = args[0] as int;
        sleep(Duration(milliseconds: millis));
        return millis;
      },
    );

    db.createFunction(
      functionName: 'isolate_name',
      argumentCount: const sqlite.AllowedArgumentCount(0),
      function: (args) {
        return Isolate.current.debugName;
      },
    );

    return db;
  }
}

void main() async {
  final db = SqliteDatabase.withFactory(TestOpenFactory(path: 'test.db'));
  await db.get('SELECT sleep(5)');
  print(await db.get('SELECT isolate_name()'));
  print(await db.execute('SELECT isolate_name()'));
  await db.close();
}
