import 'dart:async';

import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/src/web/database/connection/drift_sqlite_connection.dart';
import 'package:sqlite_async/src/web/web_mutex.dart';

/// Web implementation of [AbstractDefaultSqliteOpenFactory]
class DefaultSqliteOpenFactory
    extends AbstractDefaultSqliteOpenFactory<CommonDatabase> {
  DefaultSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()});

  @override

  /// It is possible to open a CommonDatabase in the main Dart/JS context with standard sqlite3.dart,
  /// This connection requires an external Webworker implementation for asynchronous operations.
  /// Do not use this in conjunction with async connections provided by Drift
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

  /// Currently this only uses the Drift WASM implementation.
  /// The Drift SQLite package provides built in async Web worker functionality
  /// and automatic persistence storage selection.
  /// Due to being asynchronous, the under laying CommonDatabase is not accessible
  Future<SqliteConnection> openConnection(SqliteOpenOptions options) async {
    final db = await WasmDatabase.open(
      databaseName: path,
      sqlite3Uri: Uri.parse(sqliteOptions.webSqliteOptions.wasmUri),
      driftWorkerUri: Uri.parse(sqliteOptions.webSqliteOptions.workerUri),
    );

    await db.resolvedExecutor.ensureOpen(DriftSqliteUser());

    final connection = DriftSqliteConnection(db, options.mutex ?? MutexImpl());
    // funnel table updates through the upstreamPort
    connection.updates.forEach((element) {
      options.upstreamPort?.sendPort.send(element);
    });
    return connection;
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    // WAL mode is not supported on Web
    return [];
  }
}
