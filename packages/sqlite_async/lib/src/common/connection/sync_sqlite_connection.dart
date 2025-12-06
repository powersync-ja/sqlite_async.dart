import 'dart:developer';

import 'package:sqlite3/common.dart';
import 'package:sqlite_async/src/common/mutex.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_options.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:sqlite_async/src/utils/profiler.dart';

import '../../impl/context.dart';

/// A simple "synchronous" connection which provides the async SqliteConnection
/// implementation using a synchronous SQLite connection
class SyncSqliteConnection with SqliteQueries implements SqliteConnection {
  final CommonDatabase db;
  late Mutex mutex;
  @override
  late final Stream<UpdateNotification> updates;

  bool _closed = false;

  /// Whether queries should be added to the `dart:developer` timeline.
  ///
  /// This is enabled by default outside of release builds, see
  /// [SqliteOptions.profileQueries] for details.
  final bool profileQueries;

  SyncSqliteConnection(this.db, Mutex m, {bool? profileQueries})
      : profileQueries =
            profileQueries ?? const SqliteOptions().profileQueries {
    mutex = m.open();
    updates = db.updates.map(
      (event) {
        return UpdateNotification({event.tableName});
      },
    );
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    final task = profileQueries ? TimelineTask() : null;
    task?.start('${profilerPrefix}mutex_lock');

    return mutex.lock(
      () {
        task?.finish();
        return ScopedReadContext.assumeReadLock(
          _UnsafeSyncContext(db, parent: task),
          callback,
        );
      },
      timeout: lockTimeout,
    );
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    final task = profileQueries ? TimelineTask() : null;
    task?.start('${profilerPrefix}mutex_lock');

    return mutex.lock(
      () {
        task?.finish();
        return ScopedWriteContext.assumeWriteLock(
          _UnsafeSyncContext(db, parent: task),
          callback,
        );
      },
      timeout: lockTimeout,
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
    return db.dispose();
  }

  @override
  bool get closed => _closed;

  @override
  Future<bool> getAutoCommit() async {
    return db.autocommit;
  }
}

final class _UnsafeSyncContext extends UnscopedContext {
  final TimelineTask? task;

  CommonDatabase db;

  _UnsafeSyncContext(this.db, {TimelineTask? parent})
      : task = TimelineTask(parent: parent);

  @override
  Future<T> computeWithDatabase<T>(
      Future<T> Function(CommonDatabase db) compute) {
    return compute(db);
  }

  @override
  Future<Row> get(String sql, [List<Object?> parameters = const []]) async {
    return task.timeSync(
      'get',
      () => db.select(sql, parameters).first,
      sql: sql,
      parameters: parameters,
    );
  }

  @override
  Future<ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) async {
    return task.timeSync(
      'getAll',
      () => db.select(sql, parameters),
      sql: sql,
      parameters: parameters,
    );
  }

  @override
  Future<Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) async {
    final rows = await getAll(sql, parameters);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  bool get closed => false;

  @override
  Future<bool> getAutoCommit() async {
    return db.autocommit;
  }

  @override
  Future<ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return task.timeSync(
      'execute',
      () => db.select(sql, parameters),
      sql: sql,
      parameters: parameters,
    );
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> parameterSets) async {
    task.timeSync('executeBatch', () {
      final statement = db.prepare(sql, checkNoTail: true);
      try {
        for (var parameters in parameterSets) {
          task.timeSync('iteration', () => statement.execute(parameters),
              parameters: parameters);
        }
      } finally {
        statement.dispose();
      }
    }, sql: sql);
  }

  @override
  Future<void> executeMultiple(String sql,
      [List<Object?> parameters = const []]) async {
    task.timeSync('executeMultiple', () {
      db.execute(sql, parameters);
    }, sql: sql);
  }
}
