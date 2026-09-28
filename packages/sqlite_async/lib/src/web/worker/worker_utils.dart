import 'dart:async';
import 'dart:js_interop';

import 'package:meta/meta.dart';
import 'package:sqlite3/wasm.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite_async/src/utils/shared_utils.dart';

import '../../update_notification.dart';
import '../database/broadcast_updates.dart';
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
      ClientConnection connection, CustomClientRequest request) {
    throw UnimplementedError();
  }
}

/// Worker database which handles custom requests. These requests are used for
/// handling exclusive locks for shared web workers and custom SQL execution scripts.
base class AsyncSqliteDatabase extends WorkerDatabase {
  @override
  final CommonDatabase database;
  final StreamController<UpdateNotification> _updates =
      StreamController.broadcast();
  BroadcastUpdates? _broadcastUpdates;
  StreamSubscription<UpdateNotification>? _localUpdateSubscription;
  StreamSubscription<UpdateNotification>? _remoteUpdateSubscription;

  final Map<ClientConnection, _ConnectionState> _state = {};

  AsyncSqliteDatabase({required this.database}) {
    _localUpdateSubscription = localUpdates.listen(_updates.add);
  }

  _ConnectionState _findState(ClientConnection connection) {
    return _state.putIfAbsent(connection, _ConnectionState.new);
  }

  Stream<UpdateNotification> get localUpdates {
    return database.updatedTables.map(UpdateNotification.new);
  }

  void _registerCloseListener(
      _ConnectionState state, ClientConnection connection) {
    if (!state.hasOnCloseListener) {
      state.hasOnCloseListener = true;
      connection.closed.then((_) {
        state.unsubscribeUpdates();
      });
    }
  }

  void _enableBroadcastUpdates(String name) {
    if (_broadcastUpdates == null) {
      final broadcast = _broadcastUpdates = BroadcastUpdates(name);
      // Share local updates with other tabs
      localUpdates.listen(broadcast.send);

      // Also add updates from other tabs, note that things we send aren't
      // received by our tab.
      _remoteUpdateSubscription = broadcast.updates.listen(_updates.add);
    }
  }

  @override
  void close() {
    super.close();

    _localUpdateSubscription?.cancel();
    _remoteUpdateSubscription?.cancel();
    _updates.close();
  }

  @override
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, CustomClientDatabaseRequest request) async {
    final message = request.request as BaseCustomDatabaseMessage;

    switch (message.kind) {
      case CustomDatabaseMessageKind.ok:
      case CustomDatabaseMessageKind.notifyUpdates:
        throw UnsupportedError('This is a response, not a request');
      case CustomDatabaseMessageKind.getAutoCommit:
        return database.autocommit.toJS;
      case CustomDatabaseMessageKind.executeBatch:
        final data = message as RunBatchRequest;

        await request.useLock(() {
          if (data.requireTransaction.toDart && database.autocommit) {
            throw SqliteException(
              extendedResultCode: 0,
              message:
                  'Transaction rolled back by earlier statement. Cannot execute',
              causingStatement: data.rawSql.toDart,
            );
          }

          final stmt = database.prepare(data.rawSql.toDart);
          try {
            for (final parameter in data.parameters.toDart) {
              stmt.executeWith(parameter.decodedParameters.asParameters);
            }
          } finally {
            stmt.close();
          }
        });
      case CustomDatabaseMessageKind.updateSubscriptionManagement:
        message as CustomDatabaseMessage;
        final shouldSubscribe =
            (message.rawParameters.toDart[0] as JSBoolean).toDart;
        final id = message.rawSql.toDart;
        final state = _findState(connection);

        if (shouldSubscribe) {
          state.unsubscribeUpdates();
          _registerCloseListener(state, connection);

          late StreamSubscription<void> subscription;
          subscription = state.updatesNotification =
              _updates.stream.listen((notification) {
            subscription.pause(connection.customRequest(CustomDatabaseMessage(
              CustomDatabaseMessageKind.notifyUpdates,
              id,
              notification.tables.toList(),
            )));
          });
        } else {
          state.unsubscribeUpdates();
        }
      case CustomDatabaseMessageKind.installBroadcastUpdates:
        _enableBroadcastUpdates(
            (message as InstallBroadcastUpdates).name.toDart);
    }

    return BaseCustomDatabaseMessage.okResponse();
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
  StreamSubscription<UpdateNotification>? updatesNotification;

  void unsubscribeUpdates() {
    if (updatesNotification case final active?) {
      updatesNotification = null;
      active.cancel();
    }
  }
}
