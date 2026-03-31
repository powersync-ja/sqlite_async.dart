import 'dart:async';
import 'dart:js_interop';

import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/src/web/database/broadcast_updates.dart';
import 'package:sqlite_async/src/web/web_mutex.dart';

import '../common/abstract_open_factory.dart';
import 'database.dart';
import 'update_notifications.dart';
import 'worker/worker_utils.dart';

final UpdateNotificationStreams _updateStreams = UpdateNotificationStreams();
Map<String, FutureOr<WebSqlite>> _webSQLiteImplementations = {};

/// [SqliteOpenFactory] implementation for the web.
///
/// This class can be extended to customize how databases are opened on the web.
base class WebSqliteOpenFactory extends InternalOpenFactory {
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

  WebSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()}) {
    // Make sure initializer starts running immediately
    _initialized;
  }

  /// Opens a [WebSqlite] instance for the given [options].
  ///
  /// This method can be overriden in scenarios where the way [WebSqlite] is
  /// opened needs to be customized. Implementers should be aware that the
  /// result of this method is cached and will be re-used by the open factory
  /// when provided with the same [options] again.
  Future<WebSqlite> openWebSqlite(WebSqliteOptions options) async {
    return WebSqlite.open(
      wasmModule: Uri.parse(sqliteOptions.webSqliteOptions.wasmUri),
      workers: WorkerConnector.defaultWorkers(
          Uri.parse(sqliteOptions.webSqliteOptions.workerUri)),
      controller: AsyncSqliteController(),
      handleCustomRequest: handleCustomRequest,
    );
  }

  /// Handles a custom request sent from the worker to the client.
  Future<JSAny?> handleCustomRequest(JSAny? request) {
    return _updateStreams.handleRequest(request);
  }

  /// Uses [WebSqlite] to connects to the recommended database setup for [name].
  ///
  /// This typically just calls [WebSqlite.connectToRecommended], but subclasses
  /// can customize the behavior where needed.
  Future<ConnectToRecommendedResult> connectToWorker(
      WebSqlite sqlite, String name) {
    return sqlite.connectToRecommended(name);
  }

  /// Currently this only uses the SQLite Web WASM implementation.
  /// This provides built in async Web worker functionality
  /// and automatic persistence storage selection.
  /// Due to being asynchronous, the under laying CommonDatabase is not
  /// accessible
  Future<WebDatabase> openConnection(SqliteOpenOptions options) async {
    final workers = await _initialized;
    final connection = await connectToWorker(workers, path);

    final pragmaStatements = this.pragmaStatements(options);
    if (pragmaStatements.isNotEmpty) {
      // The default implementation doesn't use pragmas on the web, but a
      // subclass might.
      await connection.database.requestLock((token) async {
        for (final stmt in pragmaStatements) {
          await connection.database.execute(stmt, token: token);
        }
      });
    }

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
        : WebMutexImpl(
            identifier: path); // Use the DB path as a mutex identifier

    BroadcastUpdates? broadcastUpdates;
    if (connection.access != AccessMode.throughSharedWorker &&
        connection.storage != StorageMode.inMemory) {
      broadcastUpdates = BroadcastUpdates(path);
    }

    return WebDatabase(
      connection.database,
      mutex,
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

  /// Obtains a stream of [UpdateNotification]s from a [database].
  ///
  /// The default implementation uses custom requests to allow workers to
  /// debounce the stream on their side to avoid messages where possible.
  Stream<UpdateNotification> updatesFor(Database database) {
    return _updateStreams.updatesFor(database);
  }
}
