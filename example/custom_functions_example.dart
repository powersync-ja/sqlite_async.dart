import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/common.dart';
import 'package:sqlite_async/sqlite_async.dart';

/// Since the functions need to be created on every SQLite connection,
/// we do this in a SqliteOpenFactory.
class TestOpenFactory extends DefaultSqliteOpenFactory {
  TestOpenFactory({required super.path, super.sqliteOptions});

  @override
  FutureOr<CommonDatabase> open(SqliteOpenOptions options) async {
    final db = await super.open(options);

    db.createFunction(
      functionName: 'sleep',
      argumentCount: const AllowedArgumentCount(1),
      function: (args) {
        final millis = args[0] as int;
        sleep(Duration(milliseconds: millis));
        return millis;
      },
    );

    db.createFunction(
      functionName: 'isolate_name',
      argumentCount: const AllowedArgumentCount(0),
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
