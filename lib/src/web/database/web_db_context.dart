import 'dart:async';

import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'executor/sqlite_executor.dart';

class WebReadContext implements SqliteReadContext {
  SQLExecutor db;

  WebReadContext(this.db);

  @override
  Future<T> computeWithDatabase<T>(
      Future<T> Function(CommonDatabase db) compute) {
    throw UnimplementedError();
  }

  @override
  Future<Row> get(String sql, [List<Object?> parameters = const []]) async {
    return (await db.select(sql, parameters)).first;
  }

  @override
  Future<ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) async {
    return db.select(sql, parameters);
  }

  @override
  Future<Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) async {
    try {
      return (await db.select(sql, parameters)).first;
    } catch (ex) {
      return null;
    }
  }

  @override
  bool get closed => throw UnimplementedError();

  @override
  Future<bool> getAutoCommit() {
    throw UnimplementedError();
  }
}

class WebWriteContext extends WebReadContext implements SqliteWriteContext {
  WebWriteContext(super.db);

  @override
  Future<ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return db.select(sql, parameters);
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> parameterSets) async {
    return db.executeBatch(sql, parameterSets);
  }
}
