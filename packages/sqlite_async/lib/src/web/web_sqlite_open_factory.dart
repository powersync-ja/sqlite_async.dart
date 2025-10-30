import 'dart:async';

import 'package:sqlite3/wasm.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/src/web/database/broadcast_updates.dart';
import 'package:sqlite_async/src/web/web_mutex.dart';
import 'package:sqlite_async/web.dart';

import 'database.dart';
import 'worker/worker_utils.dart';

Map<String, FutureOr<WebSqlite>> _webSQLiteImplementations = {};

/// Web implementation of [AbstractDefaultSqliteOpenFactory]
class DefaultSqliteOpenFactory
    extends AbstractDefaultSqliteOpenFactory<CommonDatabase>
    with WebSqliteOpenFactory {
  late final Future<WebSqlite> _initialized = Future.sync(() {
    final cacheKey = sqliteOptions.webSqliteOptions.wasmUri +
        sqliteOptions.webSqliteOptions.workerUri;

    if (_webSQLiteImplementations.containsKey(cacheKey)) {
      return _webSQLiteImplementations[cacheKey]!;
    }

    _webSQLiteImplementations[cacheKey] =
        openWebSqlite(sqliteOptions.webSqliteOptions);
    return _webSQLiteImplementations[cacheKey]!;
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
      handleCustomRequest: handleCustomRequest,
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

    // When the database is hosted in a shared worker, we don't need a local
    // mutex since that worker will hand out leases for us.
    // Additionally, package:sqlite3_web uses navigator locks internally for
    // OPFS databases.
    // Technically, the only other implementation (IndexedDB in a local context
    // or a dedicated worker) is inherently unsafe to use across tabs. But
    // wrapping those in a mutex and flushing the file system helps a little bit
    // (still something we're trying to avoid).
    final hasSqliteWebMutex =
        connection.access == AccessMode.throughSharedWorker ||
            connection.storage == StorageMode.opfs;

    final mutex = hasSqliteWebMutex
        ? null
        : MutexImpl(identifier: path); // Use the DB path as a mutex identifier

    BroadcastUpdates? broadcastUpdates;
    if (connection.access != AccessMode.throughSharedWorker &&
        connection.storage != StorageMode.inMemory) {
      broadcastUpdates = BroadcastUpdates(path);
    }

    return WebDatabase(
      connection.database,
      options.mutex ?? mutex,
      broadcastUpdates: broadcastUpdates,
      profileQueries: sqliteOptions.profileQueries,
      updates: updatesFor(connection.database),
    );
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    // WAL mode is not supported on Web
    return [];
  }
}
