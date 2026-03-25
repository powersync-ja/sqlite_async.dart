import 'dart:developer';

import 'package:meta/meta.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3_connection_pool/sqlite3_connection_pool.dart';
import 'package:sqlite_async/src/utils/profiler.dart';

import '../../impl/context.dart';

@internal
final class LeasedContext extends UnscopedContext {
  final AsyncConnection inner;
  final TimelineTask? task;

  /// Whether to throw an exception if we're about to execute a statement if
  /// the connection is in autocommit mode.
  final bool verifyInTransaction;

  @override
  bool closed = false;

  LeasedContext(this.inner, {this.task, this.verifyInTransaction = false});

  @override
  UnscopedContext interceptOutermostTransaction() {
    return LeasedContext(inner, task: task, verifyInTransaction: true);
  }

  @override
  Future<T> computeWithDatabase<T>(
      Future<T> Function(CommonDatabase db) compute) {
    return inner.unsafeAccessOnIsolate((connection) {
      return compute(connection.database);
    });
  }

  @override
  Future<ResultSet> execute(String sql, List<Object?> parameters) {
    return task.timeAsync('execute', sql: sql, parameters: parameters, () {
      return inner.unsafeAccessOnIsolate(
          _executeHelper(verifyInTransaction, sql, parameters));
    });
  }

  @override
  Future<void> executeBatch(String sql, List<dynamic> parameterSets) {
    // TODO: Make parameterSets a List<List<Object?>>
    return task.timeAsync('executeMultiple', sql: sql, () {
      final closure =
          _executeBatchHelper(verifyInTransaction, sql, parameterSets);
      return inner.unsafeAccessOnIsolate(closure);
    });
  }

  @override
  Future<void> executeMultiple(String sql) {
    return task.timeAsync('executeMultiple', sql: sql, () {
      return inner.unsafeAccessOnIsolate(
          _executeMultipleHelper(verifyInTransaction, sql));
    });
  }

  @override
  Future<ResultSet> getAll(String sql, [List<Object?> parameters = const []]) {
    return execute(sql, parameters);
  }

  @override
  Future<bool> getAutoCommit() {
    return inner.autocommit;
  }

  // Static helper functions to avoid closing over `this`.

  static ResultSet Function(PoolConnection) _executeHelper(
      bool verifyInTransaction, String sql, List<Object?> parameters) {
    return (db) {
      if (verifyInTransaction) _checkInTransaction(db.database);

      final cached = db.lookupCachedStatement(sql);
      final ResultSet resultSet;
      if (cached != null) {
        resultSet = cached.select(parameters);
        cached.reset();
      } else {
        final stmt = db.database.prepare(sql, checkNoTail: true);
        resultSet = stmt.select(parameters);
        stmt.reset();
        if (!db.storeCachedStatement(sql, stmt)) {
          stmt.close();
        }
      }

      return resultSet;
    };
  }

  static void Function(PoolConnection connection) _executeBatchHelper(
      bool verifyInTransaction, String sql, List<dynamic> parameterSets) {
    return (db) {
      if (verifyInTransaction) _checkInTransaction(db.database);

      final cached = db.lookupCachedStatement(sql);
      final stmt = cached ?? db.database.prepare(sql, checkNoTail: true);

      for (final set in parameterSets) {
        stmt.execute(set);
      }

      stmt.reset();
      if (cached == null) {
        // We've prepared the statement, so we either store it in the cache
        // or we have to close it here.
        if (!db.storeCachedStatement(sql, stmt)) {
          stmt.close();
        }
      }
    };
  }

  static void Function(PoolConnection) _executeMultipleHelper(
      bool verifyInTransaction, String sql) {
    return (db) {
      if (verifyInTransaction) _checkInTransaction(db.database);

      db.database.execute(sql);
    };
  }

  static void _checkInTransaction(CommonDatabase db) {
    if (db.autocommit) {
      throw SqliteException(
        extendedResultCode: 0,
        message: 'Transaction rolled back by earlier statement',
      );
    }
  }
}
