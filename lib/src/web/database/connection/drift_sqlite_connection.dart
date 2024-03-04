import 'dart:async';
import 'package:drift/drift.dart';
import 'package:drift/remote.dart';
import 'package:drift/wasm.dart';
import 'package:meta/meta.dart';
import 'package:sqlite_async/sqlite3_common.dart';

import 'package:sqlite_async/src/common/mutex.dart';

import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:sqlite_async/src/utils/shared_utils.dart';

/// Custom function which exposes CommonDatabase.autocommit
const sqliteAsyncAutoCommitCommand = 'sqlite_async_autocommit';

class DriftSqliteConnection with SqliteQueries implements SqliteConnection {
  WasmDatabaseResult db;

  @override
  late Stream<UpdateNotification> updates;

  final Mutex mutex;

  @override
  bool closed = false;

  DriftSqliteConnection(this.db, this.mutex) {
    // Pass on table updates
    updates = db.resolvedExecutor.streamQueries
        .updatesForSync(TableUpdateQuery.any())
        .map((tables) {
      return UpdateNotification(tables.map((e) => e.table).toSet());
    });
  }

  @override
  close() {
    closed = true;
    return db.resolvedExecutor.close();
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> parameterSets) async {
    try {
      final result = await db.resolvedExecutor.runBatched(BatchedStatements(
          [sql],
          parameterSets
              .map((e) => ArgumentsForBatchedStatement(0, e))
              .toList()));
      return result;
    } on DriftRemoteException catch (e) {
      if (e.toString().contains('SqliteException')) {
        // Drift wraps these in remote errors
        throw SqliteException(e.remoteCause.hashCode, e.remoteCause.toString());
      }
      rethrow;
    }
  }

  Future<ResultSet> select(String sql,
      [List<Object?> parameters = const []]) async {
    try {
      final result = await db.resolvedExecutor.runSelect(sql, parameters);
      if (result.isEmpty) {
        return ResultSet([], [], []);
      }
      return ResultSet(result.first.keys.toList(), [],
          result.map((e) => e.values.toList()).toList());
    } on DriftRemoteException catch (e) {
      if (e.toString().contains('SqliteException')) {
        // Drift wraps these in remote errors
        throw SqliteException(e.remoteCause.hashCode, e.remoteCause.toString());
      }
      rethrow;
    }
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout,
      String? debugContext,
      bool isTransaction = false}) async {
    return _runZoned(
        () => mutex.lock(() async {
              final context =
                  DriftReadContext(this, isTransaction: isTransaction);
              try {
                final result = await callback(context);
                return result;
              } finally {
                context.close();
              }
            }, timeout: lockTimeout),
        debugContext: debugContext ?? 'execute()');
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout,
      String? debugContext,
      bool isTransaction = false}) async {
    return _runZoned(
        () => mutex.lock(() async {
              final context =
                  DriftWriteContext(this, isTransaction: isTransaction);
              try {
                final result = await callback(context);
                return result;
              } finally {
                context.close();
              }
            }, timeout: lockTimeout),
        debugContext: debugContext ?? 'execute()');
  }

  @override
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout}) async {
    return readLock((ctx) async {
      return await internalReadTransaction(ctx, callback);
    },
        lockTimeout: lockTimeout,
        debugContext: 'readTransaction()',
        isTransaction: true);
  }

  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) async {
    return writeLock((
      ctx,
    ) async {
      return await internalWriteTransaction(ctx, callback);
    },
        lockTimeout: lockTimeout,
        debugContext: 'writeTransaction()',
        isTransaction: true);
  }

  /// The mutex on individual connections do already error in recursive locks.
  ///
  /// We duplicate the same check here, to:
  /// 1. Also error when the recursive transaction is handled by a different
  ///    connection (with a different lock).
  /// 2. Give a more specific error message when it happens.
  T _runZoned<T>(T Function() callback, {required String debugContext}) {
    if (Zone.current[this] != null) {
      throw LockError(
          'Recursive lock is not allowed. Use `tx.$debugContext` instead of `db.$debugContext`.');
    }
    var zone = Zone.current.fork(zoneValues: {this: true});
    return zone.run(callback);
  }

  @override
  Future<bool> getAutoCommit() async {
    return DriftWriteContext(this).getAutoCommit();
  }
}

class DriftReadContext implements SqliteReadContext {
  DriftSqliteConnection db;
  bool _closed = false;

  @protected
  bool isTransaction;

  DriftReadContext(this.db, {this.isTransaction = false});

  @override
  Future<T> computeWithDatabase<T>(
      Future<T> Function(CommonDatabase db) compute) {
    throw UnimplementedError();
  }

  @override
  Future<Row> get(String sql, [List<Object?> parameters = const []]) async {
    return (await getAll(sql, parameters)).first;
  }

  @override
  Future<ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) async {
    if (_closed) {
      throw SqliteException(0, 'Transaction closed', null, sql);
    }
    return db.select(sql, parameters);
  }

  @override
  Future<Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) async {
    return (await db.select(sql, parameters)).firstOrNull;
  }

  @override
  bool get closed => _closed;

  close() {
    _closed = true;
  }

  @override
  Future<bool> getAutoCommit() async {
    final response = await db.select('select $sqliteAsyncAutoCommitCommand()');
    if (response.isEmpty) {
      return false;
    }

    return response.first.values.first != 0;
  }
}

class DriftWriteContext extends DriftReadContext implements SqliteWriteContext {
  DriftWriteContext(super.db, {super.isTransaction});

  @override
  Future<ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return getAll(sql, parameters);
  }

  @override
  Future<ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) async {
    if (_closed) {
      throw SqliteException(0, 'Transaction closed', null, sql);
    }

    /// Statements in read/writeTransactions should not execute after ROLLBACK
    if (isTransaction &&
        !sql.toLowerCase().contains('begin') &&
        await getAutoCommit()) {
      throw SqliteException(0,
          'Transaction rolled back by earlier statement. Cannot execute: $sql');
    }
    return db.select(sql, parameters);
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> parameterSets) async {
    return db.executeBatch(sql, parameterSets);
  }
}

class DriftSqliteUser extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(
      QueryExecutor executor, OpeningDetails details) async {}

  @override
  int get schemaVersion => 1;
}
