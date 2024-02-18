import 'dart:async';

import 'package:sqlite3/common.dart';
import 'package:sqlite3_web/sqlite3_web.dart';

import 'package:sqlite_async/src/common/sqlite_database.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
import 'package:sqlite_async/src/update_notification.dart';

class WebDatabase
    with SqliteQueries, SqliteDatabaseMixin
    implements SqliteDatabase {
  late Future<void> _initialize;
  late Database _database;

  @override
  bool closed = false;

  WebDatabase() {
    _initialize = Future.sync(() async {
      final sqlite3 = await WebSqlite.open(
        wasmModule: Uri.parse('todo: how to specify wasm uri'),
        worker: Uri.parse('todo: how to specify worker uri'),
      );

      // todo: API in sqlite3_web to pick best possible option, similar to what
      // drift is doing.
      _database = await sqlite3.connect(
        'test',
        StorageMode.inMemory,
        AccessMode.throughSharedWorker,
      );
    });
  }

  @override
  Future<void> close() async {
    await _database.dispose();
    closed = true;
  }

  @override
  Future<bool> getAutoCommit() {
    // TODO: implement getAutoCommit
    throw UnimplementedError();
  }

  @override
  Future<void> initialize() {
    return _initialize;
  }

  @override
  Future<void> get isInitialized => _initialize;

  @override
  Never isolateConnectionFactory() {
    throw UnimplementedError();
  }

  @override
  int get maxReaders => throw UnimplementedError();

  @override
  Never get openFactory => throw UnimplementedError();

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    // todo: use customRequest API on database for lock management
    return callback(_ExlusiveContext(this));
  }

  @override
  Stream<UpdateNotification> get updates =>
      _database.updates.map((event) => UpdateNotification({event.tableName}));

  @override
  // todo: Why do we have to expose both a stream and a controller?
  StreamController<UpdateNotification> get updatesController =>
      throw UnimplementedError();

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    // todo: use customRequest API on database for lock management
    return callback(_ExlusiveContext(this));
  }
}

class _SharedContext implements SqliteReadContext {
  final WebDatabase _database;

  _SharedContext(this._database);

  @override
  bool get closed => _database.closed;

  @override
  Future<T> computeWithDatabase<T>(
      Future<T> Function(CommonDatabase db) compute) {
    // Can't be implemented: The database may live on another worker.
    throw UnimplementedError();
  }

  @override
  Future<Row> get(String sql, [List<Object?> parameters = const []]) async {
    final results = await getAll(sql, parameters);
    return results.single;
  }

  @override
  Future<ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) async {
    return await _database._database.select(sql, parameters);
  }

  @override
  Future<bool> getAutoCommit() {
    // TODO: implement getAutoCommit
    throw UnimplementedError();
  }

  @override
  Future<Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) async {
    final results = await getAll(sql, parameters);
    return results.singleOrNull;
  }
}

class _ExlusiveContext extends _SharedContext implements SqliteWriteContext {
  _ExlusiveContext(super.database);

  @override
  Future<ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return await _database._database.select(sql, parameters);
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> parameterSets) async {
    for (final set in parameterSets) {
      // use execute instead of select to avoid transferring rows from the
      // worker to this context.
      await _database._database.execute(sql, set);
    }
  }
}
