import 'dart:async';

import 'package:drift/drift.dart';
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
  Future<void> executeBatch(String sql, List<List<Object?>> parameterSets) {
    return db.resolvedExecutor.runBatched(BatchedStatements([sql],
        parameterSets.map((e) => ArgumentsForBatchedStatement(0, e)).toList()));
  }

  @override
  FutureOr<ResultSet> select(String sql,
      [List<Object?> parameters = const []]) async {
    final result = await db.resolvedExecutor.runSelect(sql, parameters);
    if (result.isEmpty) {
      return ResultSet([], [], []);
    }
    return ResultSet(result.first.keys.toList(), [],
        result.map((e) => e.values.toList()).toList());
  }
}

class DriftSqliteUser extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(
      QueryExecutor executor, OpeningDetails details) async {}

  @override
  int get schemaVersion => 1;
}
