import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/remote.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite3/common.dart';
import 'sqlite_executor.dart';

class DriftWebSQLExecutor extends SQLExecutor {
  WasmDatabaseResult db;

  @override
  bool closed = false;

  DriftWebSQLExecutor(this.db) {
    // Pass on table updates
    updateStream = db.resolvedExecutor.streamQueries
        .updatesForSync(TableUpdateQuery.any())
        .map((tables) {
      return tables.map((e) => e.table).toSet();
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

  @override
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
}

class DriftSqliteUser extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(
      QueryExecutor executor, OpeningDetails details) async {}

  @override
  int get schemaVersion => 1;
}
