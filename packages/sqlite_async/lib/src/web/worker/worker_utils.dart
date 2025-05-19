import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:meta/meta.dart';
import 'package:mutex/mutex.dart';
import 'package:sqlite3/wasm.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite3_web/protocol_utils.dart' as proto;

import 'throttled_common_database.dart';

import '../protocol.dart';

/// A base class for a web worker SQLite controller.
/// This returns an instance of [AsyncSqliteDatabase] which
/// can be extended to perform custom requests.
base class AsyncSqliteController extends DatabaseController {
  @override
  Future<WorkerDatabase> openDatabase(WasmSqlite3 sqlite3, String path,
      String vfs, JSAny? additionalData) async {
    final db = openUnderlying(sqlite3, path, vfs, additionalData);

    // Register any custom functions here if needed
    final profile = additionalData != null &&
        (additionalData as CustomOpenOptions).profileQueries?.toDart == true;

    final throttled = ThrottledCommonDatabase(db, profile);

    return AsyncSqliteDatabase(database: throttled);
  }

  /// Opens a database with the `sqlite3` package that will be wrapped in a
  /// [ThrottledCommonDatabase] for [openDatabase].
  @visibleForOverriding
  CommonDatabase openUnderlying(
    WasmSqlite3 sqlite3,
    String path,
    String vfs,
    JSAny? additionalData,
  ) {
    return sqlite3.open(path, vfs: vfs);
  }

  @override
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request) {
    throw UnimplementedError();
  }
}

/// Worker database which handles custom requests. These requests are used for
/// handling exclusive locks for shared web workers and custom SQL execution scripts.
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
        final hasTypeInfo = message.typeInfo.isDefinedAndNotNull;
        final parameters = proto.deserializeParameters(
            message.rawParameters, message.typeInfo);
        if (database.autocommit) {
          throw SqliteException(0,
              "Transaction rolled back by earlier statement. Cannot execute: $sql");
        }

        var res = database.select(sql, parameters);
        if (hasTypeInfo) {
          // If the client is sending a request that has parameters with type
          // information, it will also support a newer serialization format for
          // result sets.
          return JSObject()
            ..['format'] = 2.toJS
            ..['r'] = proto.serializeResultSet(res);
        } else {
          var dartMap = resultSetToMap(res);
          var jsObject = dartMap.jsify();
          return jsObject;
        }

      case CustomDatabaseMessageKind.executeBatchInTransaction:
        final sql = message.rawSql.toDart;
        final parameters = proto.deserializeParameters(
            message.rawParameters, message.typeInfo);
        if (database.autocommit) {
          throw SqliteException(0,
              "Transaction rolled back by earlier statement. Cannot execute: $sql");
        }
        database.execute(sql, parameters);
    }

    return CustomDatabaseMessage(CustomDatabaseMessageKind.lockObtained);
  }

  Map<String, dynamic> resultSetToMap(ResultSet resultSet) {
    var resultSetMap = <String, dynamic>{};

    resultSetMap['columnNames'] = resultSet.columnNames;
    resultSetMap['tableNames'] = resultSet.tableNames;
    resultSetMap['rows'] = resultSet.rows;

    return resultSetMap;
  }
}
