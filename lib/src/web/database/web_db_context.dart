import 'dart:async';

import 'package:meta/meta.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'executor/sqlite_executor.dart';

/// Custom function which exposes CommonDatabase.autocommit
const sqliteAsyncAutoCommitCommand = 'sqlite_async_autocommit';

class WebReadContext implements SqliteReadContext {
  SQLExecutor db;
  bool _closed = false;

  @protected
  bool isTransaction;

  WebReadContext(this.db, {this.isTransaction = false});

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
    final rows = await getAll(sql, parameters);
    return rows.isEmpty ? null : rows.first;
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

class WebWriteContext extends WebReadContext implements SqliteWriteContext {
  WebWriteContext(super.db, {super.isTransaction});

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
