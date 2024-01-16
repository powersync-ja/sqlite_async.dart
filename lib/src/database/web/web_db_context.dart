import 'dart:async';

import 'package:sqlite3/common.dart';
import 'package:sqlite_async/sqlite_async.dart';

class WebReadContext implements SqliteReadContext {
  SQLExecutor db;

  WebReadContext(SQLExecutor this.db);

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
}

class WebWriteContext extends WebReadContext implements SqliteWriteContext {
  WebWriteContext(SQLExecutor super.db);

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
