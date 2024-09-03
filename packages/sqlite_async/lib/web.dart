///
library sqlite_async.web;

import 'package:sqlite3_web/sqlite3_web.dart';
import 'sqlite_async.dart';
import 'src/web/database.dart';

/// A [SqliteConnection] interface implemented by opened connections when
/// running on the web.
///
/// This adds the [exposeEndpoint], which uses `dart:js_interop` types not
/// supported on native Dart platforms. The method can be used to access an
/// opened database across different JavaScript contexts
/// (e.g. document windows and workers).
abstract class WebSqliteConnection implements SqliteConnection {
  /// Returns a [SqliteWebEndpoint] from `package:sqlite3/web.dart` - a
  /// structure that consists only of types that can be transferred across a
  /// `MessagePort` in JavaScript.
  ///
  /// After transferring this endpoint to another JavaScript context (e.g. a
  /// worker), the worker can call [connectToEndpoint] to obtain a connection to
  /// the same sqlite database.
  Future<SqliteWebEndpoint> exposeEndpoint();

  /// Connect to an endpoint obtained through [exposeEndpoint].
  ///
  /// The endpoint is transferrable in JavaScript, allowing multiple JavaScript
  /// contexts to exchange opened database connections.
  static Future<WebSqliteConnection> connectToEndpoint(
      SqliteWebEndpoint endpoint) async {
    final rawSqlite = await WebSqlite.connectToPort(endpoint);
    final database = WebDatabase(rawSqlite, null);
    return database;
  }
}
