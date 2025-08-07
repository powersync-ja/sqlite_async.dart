import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:meta/meta.dart';
import 'package:mutex/mutex.dart';
import 'package:sqlite3/wasm.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite3_web/protocol_utils.dart' as proto;
import 'package:sqlite_async/src/utils/database_utils.dart';

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

    return AsyncSqliteDatabase(database: db);
  }

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
  final Stream<Set<String>> _updates;

  // This mutex is only used for lock requests from clients. Clients only send
  // these requests for shared workers, so we can assume each database is only
  // opened once and we don't need web locks here.
  final mutex = ReadWriteMutex();
  final Map<ClientConnection, _ConnectionState> _state = {};

  AsyncSqliteDatabase({required this.database})
      : _updates = database.throttledUpdatedTables;

  _ConnectionState _findState(ClientConnection connection) {
    return _state.putIfAbsent(connection, _ConnectionState.new);
  }

  void _markHoldsMutex(ClientConnection connection) {
    final state = _findState(connection);
    state.holdsMutex = true;
    _registerCloseListener(state, connection);
  }

  void _registerCloseListener(
      _ConnectionState state, ClientConnection connection) {
    if (!state.hasOnCloseListener) {
      state.hasOnCloseListener = true;
      connection.closed.then((_) {
        state.unsubscribeUpdates();
        if (state.holdsMutex) {
          mutex.release();
        }
      });
    }
  }

  @override
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request) async {
    final message = request as CustomDatabaseMessage;

    switch (message.kind) {
      case CustomDatabaseMessageKind.requestSharedLock:
        await mutex.acquireRead();
        _markHoldsMutex(connection);
      case CustomDatabaseMessageKind.requestExclusiveLock:
        await mutex.acquireWrite();
        _markHoldsMutex(connection);
      case CustomDatabaseMessageKind.releaseLock:
        _findState(connection).holdsMutex = false;
        mutex.release();
      case CustomDatabaseMessageKind.lockObtained:
      case CustomDatabaseMessageKind.notifyUpdates:
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
      case CustomDatabaseMessageKind.updateSubscriptionManagement:
        final shouldSubscribe = (message.rawParameters[0] as JSBoolean).toDart;
        final id = message.rawSql.toDart;
        final state = _findState(connection);

        if (shouldSubscribe) {
          state.unsubscribeUpdates();
          _registerCloseListener(state, connection);

          state.updatesNotification = _updates.listen((tables) {
            connection.customRequest(CustomDatabaseMessage(
              CustomDatabaseMessageKind.notifyUpdates,
              id,
              tables.toList(),
            ));
          });
        } else {
          state.unsubscribeUpdates();
        }
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

final class _ConnectionState {
  bool hasOnCloseListener = false;
  bool holdsMutex = false;
  StreamSubscription<Set<String>>? updatesNotification;

  void unsubscribeUpdates() {
    if (updatesNotification case final active?) {
      updatesNotification = null;
      active.cancel();
    }
  }
}
