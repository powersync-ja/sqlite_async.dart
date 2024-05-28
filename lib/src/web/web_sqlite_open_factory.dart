import 'dart:async';

import 'package:sqlite3/wasm.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/src/web/web_mutex.dart';

import 'database.dart';

Map<String, FutureOr<WebSqlite>> webSQLiteImplementations = {};

/// Web implementation of [AbstractDefaultSqliteOpenFactory]
class DefaultSqliteOpenFactory
    extends AbstractDefaultSqliteOpenFactory<CommonDatabase> {
  final Future<WebSqlite> _initialized;

  DefaultSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()})
      : _initialized = Future.sync(() {
          final cacheKey = sqliteOptions.webSqliteOptions.wasmUri +
              sqliteOptions.webSqliteOptions.workerUri;

          if (webSQLiteImplementations.containsKey(cacheKey)) {
            return webSQLiteImplementations[cacheKey]!;
          }

          webSQLiteImplementations[cacheKey] = WebSqlite.open(
            wasmModule: Uri.parse(sqliteOptions.webSqliteOptions.wasmUri),
            worker: Uri.parse(sqliteOptions.webSqliteOptions.workerUri),
          );
          return webSQLiteImplementations[cacheKey]!;
        });

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
    final workers = await _initialized;
    final connection = await workers.connectToRecommended(path);

    // When the database is accessed through a shared worker, we implement
    // mutexes over custom messages sent through the shared worker. In other
    // cases, we need to implement a mutex locally.
    final mutex = connection.access == AccessMode.throughSharedWorker
        ? null
        : MutexImpl();

    return WebDatabase(connection.database, options.mutex ?? mutex);
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    // WAL mode is not supported on Web
    return [];
  }
}
