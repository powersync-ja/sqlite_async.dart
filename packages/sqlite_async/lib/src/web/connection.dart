import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:web/web.dart';

import '../sqlite_connection.dart';
import 'database.dart';
import 'update_notifications.dart';
import 'web_mutex.dart';

const _deprecatedFlush = Deprecated(
  'The flush parameter no longer does anything, IndexedDB databases are '
  'persisted after each write lock.',
);

/// An endpoint that can be used, by any running JavaScript context in the same
/// website, to connect to an existing [WebSqliteConnection].
///
/// These endpoints are created by calling [WebSqliteConnection.exposeEndpoint]
/// and consist of a [MessagePort] and two [String]s internally identifying the
/// connection. Both objects can be transferred over send ports towards another
/// worker or context. That context can then use
/// [WebSqliteConnection.connectToEndpoint] to connect to the port already
/// opened.
typedef WebDatabaseEndpoint = ({
  MessagePort connectPort,
  String connectName,
  String? lockName,
});

/// A [SqliteConnection] interface implemented by opened connections when
/// running on the web.
///
/// This adds the [exposeEndpoint], which uses `dart:js_interop` types not
/// supported on native Dart platforms. The method can be used to access an
/// opened database across different JavaScript contexts
/// (e.g. document windows and workers).
abstract class WebSqliteConnection implements SqliteConnection {
  /// Returns a future that completes when this connection is closed.
  ///
  /// This usually only happens when calling [close], but on the web
  /// specifically, it can also happen when a remote context closes a database
  /// accessed via [connectToEndpoint].
  Future<void> get closedFuture;

  /// Returns a [WebDatabaseEndpoint] - a structure that consists only of types
  /// that can be transferred across a [MessagePort] in JavaScript.
  ///
  /// After transferring this endpoint to another JavaScript context (e.g. a
  /// worker), the worker can call [connectToEndpoint] to obtain a connection to
  /// the same sqlite database.
  Future<WebDatabaseEndpoint> exposeEndpoint();

  /// Connect to an endpoint obtained through [exposeEndpoint].
  ///
  /// The endpoint is transferrable in JavaScript, allowing multiple JavaScript
  /// contexts to exchange opened database connections.
  static Future<WebSqliteConnection> connectToEndpoint(
      WebDatabaseEndpoint endpoint) async {
    final updates = UpdateNotificationStreams();
    final rawSqlite = await WebSqlite.connectToPort(
      (endpoint.connectPort, endpoint.connectName),
      handleCustomRequest: updates.handleRequest,
    );

    final database = WebDatabase(
      rawSqlite,
      switch (endpoint.lockName) {
        var lock? => WebMutexImpl(identifier: lock),
        null => null,
      },
      profileQueries: false,
      updates: updates.updatesFor(rawSqlite),
    );
    return database;
  }

  /// Same as [SqliteConnection.writeLock].
  ///
  /// Has an additional [flush] (defaults to true). This can be set to false
  /// to delay flushing changes to the database file, losing durability guarantees.
  /// This only has an effect when IndexedDB storage is used.
  ///
  /// See [WebSqliteConnection.flush] for details.
  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout,
      String? debugContext,
      @_deprecatedFlush bool? flush});

  @override
  Future<T> abortableWriteLock<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Future<void>? abortTrigger,
      String? debugContext,
      @_deprecatedFlush bool? flush});

  /// Same as [SqliteConnection.writeTransaction].
  ///
  /// Has an additional [flush] (defaults to true). This can be set to false
  /// to delay flushing changes to the database file, losing durability guarantees.
  /// This only has an effect when IndexedDB storage is used.
  ///
  /// See [WebSqliteConnection.flush] for details.
  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout,
      @_deprecatedFlush bool? flush});

  /// Flush changes to the underlying storage.
  ///
  /// In older versions of the `sqlite3` package, writes on IndexedDB databases
  /// used to be asynchronous and might not complete if a tab writing to a
  /// database was closed shortly after making its write.
  ///
  /// This is no longer an issue, recent versions persist changes in an
  /// IndexedDB transaction before the transaction completes. Thus, this method
  /// is deprecated and should not be used anymore.
  @_deprecatedFlush
  Future<void> flush();
}
