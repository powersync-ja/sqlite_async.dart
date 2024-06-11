import 'dart:js_interop';
import 'dart:js_util' as js_util;

import 'package:mutex/mutex.dart';
import 'package:sqlite3/wasm.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite_async/sqlite3_common.dart';

import '../protocol.dart';

base class AsyncSqliteController extends DatabaseController {
  @override
  Future<WorkerDatabase> openDatabase(
      WasmSqlite3 sqlite3, String path, String vfs) async {
    final db = sqlite3.open(path, vfs: vfs);

    // Register any custom functions here if needed

    return AsyncSqliteDatabase(database: db);
  }

  @override
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request) {
    throw UnimplementedError();
  }
}

class AsyncSqliteDatabase extends WorkerDatabase {
  @override
  final CommonDatabase database;

  // This mutex is only used for lock requests from clients. Clients only send
  // these requests for shared workers, so we can assume each database is only
  // opened once and we don't need web locks here.
  final mutex = ReadWriteMutex();

  AsyncSqliteDatabase({required this.database});

  @override
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request) async {
    final message = request as CustomDatabaseMessage;

    switch (message.kind) {
      case CustomDatabaseMessageKind.requestSharedLock:
        await mutex.acquireRead();
      case CustomDatabaseMessageKind.requestExclusiveLock:
        await mutex.acquireWrite();
      case CustomDatabaseMessageKind.releaseLock:
        mutex.release();
      case CustomDatabaseMessageKind.lockObtained:
        throw UnsupportedError('This is a response, not a request');
      case CustomDatabaseMessageKind.getAutoCommit:
        return database.autocommit.toJS;
      case CustomDatabaseMessageKind.executeInTransaction:
        final sql = message.rawSql.toDart;
        final parameters = [
          for (final raw in (message.rawParameters).toDart) raw.dartify()
        ];
        if (database.autocommit && !sql.toLowerCase().contains('begin')) {
          throw SqliteException(0,
              "Transaction rolled back by earlier statement. Cannot execute: $sql");
        }
        var res = database.select(sql, parameters);

        var dartObject = resultSetToDartMap(res);

        var jsObject = js_util.jsify(dartObject);

        return jsObject;
      case CustomDatabaseMessageKind.executeBatchInTransaction:
        final sql = message.rawSql.toDart;
        final parameters = [
          for (final raw in (message.rawParameters).toDart) raw.dartify()
        ];
        if (database.autocommit && !sql.toLowerCase().contains('begin')) {
          throw SqliteException(0,
              "Transaction rolled back by earlier statement. Cannot execute: $sql");
        }
        database.execute(sql, parameters);
    }

    return CustomDatabaseMessage(CustomDatabaseMessageKind.lockObtained);
  }

  Map<String, dynamic> resultSetToDartMap(ResultSet resultSet) {
    var dartObject = <String, dynamic>{};

    dartObject['columnNames'] = resultSet.columnNames;
    dartObject['tableNames'] = resultSet.tableNames;
    dartObject['rows'] = resultSet.rows;

    return dartObject;
  }
}
