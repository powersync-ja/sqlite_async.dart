import 'dart:async';

import 'package:sqlite3/wasm.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/src/web/database/broadcast_updates.dart';
import 'package:sqlite_async/src/web/web_mutex.dart';
import 'package:sqlite_async/web.dart';

import 'database.dart';
import 'worker/worker_utils.dart';

Map<String, FutureOr<WebSqlite>> webSQLiteImplementations = {};

/// Web implementation of [AbstractDefaultSqliteOpenFactory]
class DefaultSqliteOpenFactory
    extends AbstractDefaultSqliteOpenFactory<CommonDatabase>
    with WebSqliteOpenFactory {
  late final Future<WebSqlite> _initialized = Future.sync(() {
    final cacheKey = sqliteOptions.webSqliteOptions.wasmUri +
        sqliteOptions.webSqliteOptions.workerUri;

    if (webSQLiteImplementations.containsKey(cacheKey)) {
      return webSQLiteImplementations[cacheKey]!;
    }

    webSQLiteImplementations[cacheKey] =
        openWebSqlite(sqliteOptions.webSqliteOptions);
    return webSQLiteImplementations[cacheKey]!;
  });

  DefaultSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()}) {
    // Make sure initializer starts running immediately
    _initialized;
  }

  @override
  Future<WebSqlite> openWebSqlite(WebSqliteOptions options) async {
    return WebSqlite.open(
      wasmModule: Uri.parse(sqliteOptions.webSqliteOptions.wasmUri),
      worker: Uri.parse(sqliteOptions.webSqliteOptions.workerUri),
      controller: AsyncSqliteController(),
    );
  }

  /// This is currently not supported on web
  @override
  CommonDatabase openDB(SqliteOpenOptions options) {
    throw UnimplementedError(
        'Direct access to CommonDatabase is not available on web.');
  }

  @override

  /// Currently this only uses the SQLite Web WASM implementation.
  /// This provides built in async Web worker functionality
  /// and automatic persistence storage selection.
  /// Due to being asynchronous, the under laying CommonDatabase is not accessible
  Future<SqliteConnection> openConnection(SqliteOpenOptions options) async {
    final workers = await _initialized;
    final connection = await connectToWorker(workers, path);

    // When the database is accessed through a shared worker, we implement
    // mutexes over custom messages sent through the shared worker. In other
    // cases, we need to implement a mutex locally.
    final mutex = connection.access == AccessMode.throughSharedWorker
        ? null
        : MutexImpl(identifier: path); // Use the DB path as a mutex identifier

    BroadcastUpdates? updates;
    if (connection.access != AccessMode.throughSharedWorker &&
        connection.storage != StorageMode.inMemory) {
      updates = BroadcastUpdates(path);
    }

    return WebDatabase(connection.database, options.mutex ?? mutex,
        broadcastUpdates: updates);
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    // WAL mode is not supported on Web
    return [];
  }
}
