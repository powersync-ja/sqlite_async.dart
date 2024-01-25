import 'dart:async';

import 'package:drift/wasm.dart';
import 'package:sqlite_async/src/database/web/executor/drift_sql_executor.dart';
import 'package:sqlite_async/src/database/web/executor/sqlite_executor.dart';
import 'package:sqlite_async/src/sqlite_options.dart';
import '../abstract_open_factory.dart';
import 'package:sqlite3/wasm.dart';

class DefaultSqliteOpenFactoryImplementation
    extends AbstractDefaultSqliteOpenFactory<CommonDatabase> {
  DefaultSqliteOpenFactoryImplementation(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()});

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

  /// Returns a simple asynchronous SQLExecutor which can be used to implement
  /// higher order functionality.
  /// Currently this only uses the Drift WASM implementation.
  /// The Drift SQLite package provides built in async Web worker functionality
  /// and automatic persistence storage selection.
  /// Due to being asynchronous, the under laying CommonDatabase is not accessible
  Future<SQLExecutor> openExecutor(SqliteOpenOptions options) async {
    final db = await WasmDatabase.open(
      databaseName: path,
      sqlite3Uri: Uri.parse(sqliteOptions.webSqliteOptions.wasmUri),
      driftWorkerUri: Uri.parse(sqliteOptions.webSqliteOptions.workerUri),
    );

    final executor = DriftWebSQLExecutor(db);
    await db.resolvedExecutor.ensureOpen(DriftSqliteUser());

    return executor;
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    // WAL mode is not supported on Web
    return [];
  }
}
