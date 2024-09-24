import 'package:sqlite3/common.dart';
import 'package:sqlite_async/src/common/mutex.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
import 'package:sqlite_async/src/update_notification.dart';

/// A simple "synchronous" connection which provides the async SqliteConnection
/// implementation using a synchronous SQLite connection
class SyncSqliteConnection extends SqliteConnection with SqliteQueries {
  final CommonDatabase db;
  late Mutex mutex;
  @override
  late final Stream<UpdateNotification> updates;

  bool _closed = false;

  SyncSqliteConnection(this.db, Mutex m) {
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
    return mutex.lock(() => callback(SyncReadContext(db)),
        timeout: lockTimeout);
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    return mutex.lock(() => callback(SyncWriteContext(db)),
        timeout: lockTimeout);
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

  @override
  int getNumConnections() {
    return -1;
  }
}

class SyncReadContext implements SqliteReadContext {
  CommonDatabase db;

  SyncReadContext(this.db);

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
  SyncWriteContext(super.db);

  @override
  Future<ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return db.select(sql, parameters);
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> parameterSets) async {
    return computeWithDatabase((db) async {
      final statement = db.prepare(sql, checkNoTail: true);
      try {
        for (var parameters in parameterSets) {
          statement.execute(parameters);
        }
      } finally {
        statement.dispose();
      }
    });
  }
}
