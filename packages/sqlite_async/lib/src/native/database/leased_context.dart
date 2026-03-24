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

  @override
  bool closed = false;

  LeasedContext(this.inner, [this.task]);

  @override
  Future<T> computeWithDatabase<T>(
      Future<T> Function(CommonDatabase db) compute) {
    return inner.unsafeAccessOnIsolate((connection) {
      return compute(connection.database);
    });
  }

  @override
  Future<ResultSet> execute(String sql, List<Object?> parameters) {
    return task.timeAsync('execute', sql: sql, parameters: parameters,
        () async {
      final (rs, _) = await inner.select(sql, parameters);
      return rs;
    });
  }

  @override
  Future<void> executeBatch(String sql, List<dynamic> parameterSets) {
    // TODO: Make parameterSets a List<List<Object>>
    return task.timeAsync('executeMultiple', sql: sql, () {
      return inner.unsafeAccessOnIsolate((db) {
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
      });
    });
  }

  @override
  Future<void> executeMultiple(String sql) {
    return task.timeAsync('executeMultiple', sql: sql, () {
      return inner.unsafeAccessOnIsolate((db) {
        db.database.execute(sql);
      });
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
}
