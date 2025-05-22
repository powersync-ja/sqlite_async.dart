import 'dart:async';
import 'dart:developer';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:sqlite3/common.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite3_web/protocol_utils.dart' as proto;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/src/utils/profiler.dart';
import 'package:sqlite_async/src/utils/shared_utils.dart';
import 'package:sqlite_async/src/web/database/broadcast_updates.dart';
import 'package:sqlite_async/web.dart';
import 'protocol.dart';
import 'web_mutex.dart';

class WebDatabase
    with SqliteQueries, SqliteDatabaseMixin
    implements SqliteDatabase, WebSqliteConnection {
  final Database _database;
  final Mutex? _mutex;
  final bool profileQueries;

  /// For persistent databases that aren't backed by a shared worker, we use
  /// web broadcast channels to forward local update events to other tabs.
  final BroadcastUpdates? broadcastUpdates;

  @override
  bool closed = false;

  WebDatabase(
    this._database,
    this._mutex, {
    required this.profileQueries,
    this.broadcastUpdates,
  });

  @override
  Future<void> close() async {
    await _database.dispose();
    closed = true;
  }

  @override
  Future<void> get closedFuture => _database.closed;

  @override
  Future<bool> getAutoCommit() async {
    final response = await _database.customRequest(
        CustomDatabaseMessage(CustomDatabaseMessageKind.getAutoCommit));
    return (response as JSBoolean?)?.toDart ?? false;
  }

  @override
  Future<void> initialize() {
    return Future.value();
  }

  @override
  Future<void> get isInitialized => initialize();

  @override

  /// Not relevant for web.
  Never isolateConnectionFactory() {
    throw UnimplementedError();
  }

  @override

  /// Not supported on web. There is only 1 connection.
  int get maxReaders => throw UnimplementedError();

  @override

  /// Not relevant for web.
  Never get openFactory => throw UnimplementedError();

  @override
  Future<WebDatabaseEndpoint> exposeEndpoint() async {
    final endpoint = await _database.additionalConnection();

    return (
      connectPort: endpoint.$1,
      connectName: endpoint.$2,
      lockName: switch (_mutex) {
        MutexImpl(:final resolvedIdentifier) => resolvedIdentifier,
        _ => null,
      },
    );
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    if (_mutex case var mutex?) {
      return await mutex.lock(() async {
        final context = _SharedContext(this);
        try {
          return await callback(context);
        } finally {
          context.markClosed();
        }
      });
    } else {
      // No custom mutex, coordinate locks through shared worker.
      await _database.customRequest(
          CustomDatabaseMessage(CustomDatabaseMessageKind.requestSharedLock));

      try {
        return await callback(_SharedContext(this));
      } finally {
        await _database.customRequest(
            CustomDatabaseMessage(CustomDatabaseMessageKind.releaseLock));
      }
    }
  }

  @override
  Stream<UpdateNotification> get updates =>
      _database.updates.map((event) => UpdateNotification({event.tableName}));

  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout,
      bool? flush}) {
    return writeLock(
        (writeContext) =>
            internalWriteTransaction(writeContext, (context) async {
              // All execute calls done in the callback will be checked for the
              // autocommit state
              return callback(_ExclusiveTransactionContext(this, writeContext));
            }),
        debugContext: 'writeTransaction()',
        lockTimeout: lockTimeout,
        flush: flush);
  }

  @override

  /// Internal writeLock which intercepts transaction context's to verify auto commit is not active
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext, bool? flush}) async {
    if (_mutex case var mutex?) {
      return await mutex.lock(() async {
        final context = _ExclusiveContext(this);
        try {
          return await callback(context);
        } finally {
          context.markClosed();
          if (flush != false) {
            await this.flush();
          }
        }
      });
    } else {
      // No custom mutex, coordinate locks through shared worker.
      await _database.customRequest(CustomDatabaseMessage(
          CustomDatabaseMessageKind.requestExclusiveLock));
      final context = _ExclusiveContext(this);
      try {
        return await callback(context);
      } finally {
        context.markClosed();
        if (flush != false) {
          await this.flush();
        }
        await _database.customRequest(
            CustomDatabaseMessage(CustomDatabaseMessageKind.releaseLock));
      }
    }
  }

  @override
  Future<void> flush() async {
    await isInitialized;
    return _database.fileSystem.flush();
  }
}

class _SharedContext implements SqliteReadContext {
  final WebDatabase _database;
  bool _contextClosed = false;

  final TimelineTask? _task;

  _SharedContext(this._database)
      : _task = _database.profileQueries ? TimelineTask() : null;

  @override
  bool get closed => _contextClosed || _database.closed;

  @override
  Future<T> computeWithDatabase<T>(
      Future<T> Function(CommonDatabase db) compute) {
    // Can't be implemented: The database may live on another worker.
    throw UnimplementedError();
  }

  @override
  Future<Row> get(String sql, [List<Object?> parameters = const []]) async {
    final results = await getAll(sql, parameters);
    return results.first;
  }

  @override
  Future<ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) async {
    return _task.timeAsync(
      'getAll',
      sql: sql,
      parameters: parameters,
      () async {
        return await wrapSqliteException(
            () => _database._database.select(sql, parameters));
      },
    );
  }

  @override
  Future<bool> getAutoCommit() async {
    return _database.getAutoCommit();
  }

  @override
  Future<Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) async {
    final results = await getAll(sql, parameters);
    return results.firstOrNull;
  }

  void markClosed() {
    _contextClosed = true;
  }
}

class _ExclusiveContext extends _SharedContext implements SqliteWriteContext {
  _ExclusiveContext(super.database);

  @override
  Future<ResultSet> execute(String sql, [List<Object?> parameters = const []]) {
    return _task.timeAsync('execute', sql: sql, parameters: parameters, () {
      return wrapSqliteException(
          () => _database._database.select(sql, parameters));
    });
  }

  @override
  Future<void> executeBatch(String sql, List<List<Object?>> parameterSets) {
    return _task.timeAsync('executeBatch', sql: sql, () {
      return wrapSqliteException(() async {
        for (final set in parameterSets) {
          // use execute instead of select to avoid transferring rows from the
          // worker to this context.
          await _database._database.execute(sql, set);
        }
      });
    });
  }
}

class _ExclusiveTransactionContext extends _ExclusiveContext {
  SqliteWriteContext baseContext;

  _ExclusiveTransactionContext(super.database, this.baseContext);

  @override
  bool get closed => baseContext.closed;

  Future<ResultSet> _executeInternal(
      String sql, List<Object?> parameters) async {
    // Operations inside transactions are executed with custom requests
    // in order to verify that the connection does not have autocommit enabled.
    // The worker will check if autocommit = true before executing the SQL.
    // An exception will be thrown if autocommit is enabled.
    // The custom request which does the above will return the ResultSet as a formatted
    // JavaScript object. This is the converted into a Dart ResultSet.
    return await wrapSqliteException(() async {
      var res = await _database._database.customRequest(CustomDatabaseMessage(
              CustomDatabaseMessageKind.executeInTransaction, sql, parameters))
          as JSObject;

      if (res.has('format') && (res['format'] as JSNumber).toDartInt == 2) {
        // Newer workers use a serialization format more efficient than dartify().
        return proto.deserializeResultSet(res['r'] as JSObject);
      }

      var result = Map<String, dynamic>.from(res.dartify() as Map);
      final columnNames = [
        for (final entry in result['columnNames']) entry as String
      ];
      final rawTableNames = result['tableNames'];
      final tableNames = rawTableNames != null
          ? [
              for (final entry in (rawTableNames as List<Object?>))
                entry as String
            ]
          : null;

      final rows = <List<Object?>>[];
      for (final row in (result['rows'] as List<Object?>)) {
        final dartRow = <Object?>[];

        for (final column in (row as List<Object?>)) {
          dartRow.add(column);
        }

        rows.add(dartRow);
      }
      final resultSet = ResultSet(columnNames, tableNames, rows);
      return resultSet;
    });
  }

  @override
  Future<ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return _task.timeAsync('execute', sql: sql, parameters: parameters, () {
      return _executeInternal(sql, parameters);
    });
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> parameterSets) async {
    return _task.timeAsync('executeBatch', sql: sql, () async {
      for (final set in parameterSets) {
        await _database._database.customRequest(CustomDatabaseMessage(
            CustomDatabaseMessageKind.executeBatchInTransaction, sql, set));
      }
    });
  }
}

/// Throws SqliteException if the Remote Exception is a SqliteException
Future<T> wrapSqliteException<T>(Future<T> Function() callback) async {
  try {
    return await callback();
  } on RemoteException catch (ex) {
    if (ex.exception case final serializedCause?) {
      throw serializedCause;
    }

    // Older versions of package:sqlite_web reported SqliteExceptions as strings
    // only.
    if (ex.toString().contains('SqliteException')) {
      RegExp regExp = RegExp(r'SqliteException\((\d+)\)');
      throw SqliteException(
          int.parse(regExp.firstMatch(ex.message)?.group(1) ?? '0'),
          ex.message);
    }
    rethrow;
  }
}
