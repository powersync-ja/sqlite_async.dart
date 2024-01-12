import 'package:sqlite3/common.dart';
import 'package:sqlite_async/sqlite_async.dart';

class WebReadContext implements SqliteReadContext {
  CommonDatabase db;

  WebReadContext(CommonDatabase this.db);

  @override
  Future<T> computeWithDatabase<T>(
      Future<T> Function(CommonDatabase db) compute) {
    return compute(db);
  }

  @override
  Future<Row> get(String sql, [List<Object?> parameters = const []]) async {
    return db.select(sql, parameters).first;
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
      return db.select(sql, parameters).first;
    } catch (ex) {
      return null;
    }
  }
}

class WebWriteContext extends WebReadContext implements SqliteWriteContext {
  WebWriteContext(CommonDatabase super.db);

  @override
  Future<ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    final result = db.select(sql, parameters);
    return result;
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> parameterSets) async {
    final statement = db.prepare(sql, checkNoTail: true);
    try {
      for (var parameters in parameterSets) {
        statement.execute(parameters);
      }
    } finally {
      statement.dispose();
    }
  }
}
