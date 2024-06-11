import 'dart:async';
import 'dart:js_interop';

import 'package:sqlite3/common.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite_async/mutex.dart';
import 'package:sqlite_async/src/common/sqlite_database.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:sqlite_async/src/utils/shared_utils.dart';
import 'protocol.dart';

class WebDatabase
    with SqliteQueries, SqliteDatabaseMixin
    implements SqliteDatabase {
  final Database _database;
  final Mutex? _mutex;

  @override
  bool closed = false;

  WebDatabase(this._database, this._mutex);

  @override
  Future<void> close() async {
    await _database.dispose();
    closed = true;
  }

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
  Never isolateConnectionFactory() {
    throw UnimplementedError();
  }

  @override
  int get maxReaders => throw UnimplementedError();

  @override
  Never get openFactory => throw UnimplementedError();

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
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    return _writeLock(callback,
        lockTimeout: lockTimeout, debugContext: debugContext);
  }

  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) {
    return _writeLock((ctx) => internalWriteTransaction(ctx, callback),
        debugContext: 'writeTransaction()',
        isTransaction: true,
        lockTimeout: lockTimeout);
  }

  /// Internal writeLock which intercepts transaction context's to verify auto commit is not active
  Future<T> _writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout,
      String? debugContext,
      bool isTransaction = false}) async {
    if (_mutex case var mutex?) {
      return await mutex.lock(() async {
        final context = isTransaction
            ? _ExclusiveTransactionContext(this)
            : _ExclusiveContext(this);
        try {
          return await callback(context);
        } finally {
          context.markClosed();
        }
      });
    } else {
      // No custom mutex, coordinate locks through shared worker.
      await _database.customRequest(CustomDatabaseMessage(
          CustomDatabaseMessageKind.requestExclusiveLock));
      final context = isTransaction
          ? _ExclusiveTransactionContext(this)
          : _ExclusiveContext(this);
      ;

      try {
        return await callback(context);
      } finally {
        context.markClosed();
        await _database.customRequest(
            CustomDatabaseMessage(CustomDatabaseMessageKind.releaseLock));
      }
    }
  }
}

class _SharedContext implements SqliteReadContext {
  final WebDatabase _database;
  bool _contextClosed = false;

  _SharedContext(this._database);

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
    return results.single;
  }

  @override
  Future<ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) async {
    return await wrapSqliteException(
        () => _database._database.select(sql, parameters));
  }

  @override
  Future<bool> getAutoCommit() async {
    return _database.getAutoCommit();
  }

  @override
  Future<Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) async {
    final results = await getAll(sql, parameters);
    return results.singleOrNull;
  }

  void markClosed() {
    _contextClosed = true;
  }
}

class _ExclusiveContext extends _SharedContext implements SqliteWriteContext {
  _ExclusiveContext(super.database);

  @override
  Future<ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return wrapSqliteException(
        () => _database._database.select(sql, parameters));
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> parameterSets) async {
    return wrapSqliteException(() async {
      for (final set in parameterSets) {
        // use execute instead of select to avoid transferring rows from the
        // worker to this context.
        await _database._database.execute(sql, set);
      }
    });
  }
}

class _ExclusiveTransactionContext extends _ExclusiveContext {
  _ExclusiveTransactionContext(super.database);

  @override
  Future<ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    var res = await _database._database.customRequest(CustomDatabaseMessage(
        CustomDatabaseMessageKind.executeInTransaction, sql, parameters));
    var result = Map<String, dynamic>.from((res as JSObject).dartify() as Map);
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
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> parameterSets) async {
    for (final set in parameterSets) {
      await _database._database.customRequest(CustomDatabaseMessage(
          CustomDatabaseMessageKind.executeBatchInTransaction, sql, set));
    }
    return;
  }
}

/// Throws SqliteException if the Remote Exception is a SqliteException
Future<T> wrapSqliteException<T>(Future<T> Function() callback) async {
  try {
    return await callback();
  } on RemoteException catch (ex) {
    if (ex.toString().contains('SqliteException')) {
      RegExp regExp = RegExp(r'SqliteException\((\d+)\)');
      // Drift wraps these in remote errors
      throw SqliteException(
          int.parse(regExp.firstMatch(ex.message)?.group(1) ?? '0'),
          ex.message);
    }
    rethrow;
  }
}
