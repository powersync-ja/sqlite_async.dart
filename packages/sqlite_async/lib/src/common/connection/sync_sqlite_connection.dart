import 'dart:developer';

import 'package:sqlite3/common.dart';
import 'package:sqlite_async/src/common/mutex.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:sqlite_async/src/utils/profiler.dart';

/// A simple "synchronous" connection which provides the async SqliteConnection
/// implementation using a synchronous SQLite connection
class SyncSqliteConnection extends SqliteConnection with SqliteQueries {
  final CommonDatabase db;
  late Mutex mutex;
  @override
  late final Stream<UpdateNotification> updates;

  bool _closed = false;

  /// Whether queries should be added to the `dart:developer` timeline.
  ///
  /// This is disabled by default.
  final bool profileQueries;

  SyncSqliteConnection(this.db, Mutex m, {this.profileQueries = false}) {
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
    task?.start('mutex_lock');

    return mutex.lock(
      () {
        task?.finish();
        return callback(SyncReadContext(db, parent: task));
      },
      timeout: lockTimeout,
    );
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    final task = profileQueries ? TimelineTask() : null;
    task?.start('mutex_lock');

    return mutex.lock(
      () {
        task?.finish();
        return callback(SyncWriteContext(db));
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

class SyncReadContext implements SqliteReadContext {
  final TimelineTask? task;

  CommonDatabase db;

  SyncReadContext(this.db, {TimelineTask? parent})
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
      arguments: timelineArgs(sql, parameters),
    );
  }

  @override
  Future<ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) async {
    return task.timeSync(
      'getAll',
      () => db.select(sql, parameters),
      arguments: timelineArgs(sql, parameters),
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
}

class SyncWriteContext extends SyncReadContext implements SqliteWriteContext {
  SyncWriteContext(super.db, {super.parent});

  @override
  Future<ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return task.timeSync(
      'execute',
      () => db.select(sql, parameters),
      arguments: timelineArgs(sql, parameters),
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
              arguments: parameterArgs(parameters));
        }
      } finally {
        statement.dispose();
      }
    }, arguments: {'sql': sql});
  }
}
