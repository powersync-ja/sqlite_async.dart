import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_options.dart';
import 'package:sqlite3/wasm.dart';
import '../abstract_open_factory.dart';

class DriftWebSQLExecutor extends SQLExecutor {
  WasmDatabaseResult db;
  final StreamController<Set<String>> updatesController =
      StreamController.broadcast();

  DriftWebSQLExecutor(WasmDatabaseResult this.db) {
    // Pass on table updates
    db.resolvedExecutor.streamQueries
        .updatesForSync(TableUpdateQuery.any())
        .forEach((tables) {
      updatesController.add(tables.map((e) => e.table).toSet());
    });
    updateStream = updatesController.stream;
  }

  @override
  close() {
    return db.resolvedExecutor.close();
  }

  @override
  Future<void> executeBatch(String sql, List<List<Object?>> parameterSets) {
    return db.resolvedExecutor.runBatched(BatchedStatements(
        [sql], [ArgumentsForBatchedStatement(0, parameterSets)]));
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

class SqliteUser extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(
      QueryExecutor executor, OpeningDetails details) async {}

  @override
  int get schemaVersion => 1;
}

class DefaultSqliteOpenFactory
    extends AbstractDefaultSqliteOpenFactory<CommonDatabase> {
  // TODO only 1 connection for now
  SQLExecutor? executor;

  DefaultSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()}) {}

  @override

  /// It is possible to open a CommonDatabase in the main Dart/JS context with standard sqlite3.dart,
  /// This connection requires an external Webworker implementation for asynchronous operations.
  Future<CommonDatabase> openDB(SqliteOpenOptions options) async {
    final wasmSqlite = await WasmSqlite3.loadFromUrl(
        Uri.parse(sqliteOptions.webSqliteOptions.wasmUri));

    wasmSqlite.registerVirtualFileSystem(
      await IndexedDbFileSystem.open(dbName: path),
      makeDefault: true,
    );

    return wasmSqlite.open(path);
  }

  @override

  /// The Drift SQLite package provides built in async Webworker functionality
  /// and automatic persistence storage selection.
  /// Due to being asynchronous, the underlaying CommonDatabase is not accessible
  Future<SQLExecutor> openWeb(SqliteOpenOptions options) async {
    if (executor != null) {
      return executor!;
    }

    final db = await WasmDatabase.open(
      databaseName: path,
      sqlite3Uri: Uri.parse(sqliteOptions.webSqliteOptions.wasmUri),
      driftWorkerUri: Uri.parse(sqliteOptions.webSqliteOptions.workerUri),
    );

    await db.resolvedExecutor.ensureOpen(SqliteUser());
    executor = DriftWebSQLExecutor(db);

    return executor!;
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    // WAL mode is not supported on Web
    return [];
  }
}
