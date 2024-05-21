import 'dart:async';

import 'package:meta/meta.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/common/isolate_connection_factory.dart';
import 'package:sqlite_async/src/impl/sqlite_database_impl.dart';
import 'package:sqlite_async/src/sqlite_options.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';

mixin SqliteDatabaseMixin implements SqliteConnection, SqliteQueries {
  /// Maximum number of concurrent read transactions.
  int get maxReaders;

  /// Factory that opens a raw database connection in each isolate.
  ///
  /// This must be safe to pass to different isolates.
  ///
  /// Use a custom class for this to customize the open process.
  AbstractDefaultSqliteOpenFactory get openFactory;

  /// Use this stream to subscribe to notifications of updates to tables.
  @override
  Stream<UpdateNotification> get updates;

  @protected
  Future<void> get isInitialized;

  /// Wait for initialization to complete.
  ///
  /// While initializing is automatic, this helps to catch and report initialization errors.
  Future<void> initialize() async {
    await isInitialized;
  }

  /// A connection factory that can be passed to different isolates.
  ///
  /// Use this to access the database in background isolates.
  IsolateConnectionFactory isolateConnectionFactory();
}

/// A SQLite database instance.
///
/// Use one instance per database file. If multiple instances are used, update
/// notifications may not trigger, and calls may fail with "SQLITE_BUSY" errors.
abstract class SqliteDatabase
    with SqliteQueries, SqliteDatabaseMixin
    implements SqliteConnection {
  /// The maximum number of concurrent read transactions if not explicitly specified.
  static const int defaultMaxReaders = 5;

  /// Open a SqliteDatabase.
  ///
  /// Only a single SqliteDatabase per [path] should be opened at a time.
  ///
  /// A connection pool is used by default, allowing multiple concurrent read
  /// transactions, and a single concurrent write transaction. Write transactions
  /// do not block read transactions, and read transactions will see the state
  /// from the last committed write transaction.
  ///
  /// A maximum of [maxReaders] concurrent read transactions are allowed.
  factory SqliteDatabase(
      {required path,
      int maxReaders = SqliteDatabase.defaultMaxReaders,
      SqliteOptions options = const SqliteOptions.defaults()}) {
    return SqliteDatabaseImpl(
        path: path, maxReaders: maxReaders, options: options);
  }

  /// Advanced: Open a database with a specified factory.
  ///
  /// The factory is used to open each database connection in background isolates.
  ///
  /// Use when control is required over the opening process. Examples include:
  ///  1. Specifying the path to `libsqlite.so` on Linux.
  ///  2. Running additional per-connection PRAGMA statements on each connection.
  ///  3. Creating custom SQLite functions.
  ///  4. Creating temporary views or triggers.
  factory SqliteDatabase.withFactory(
      AbstractDefaultSqliteOpenFactory openFactory,
      {int maxReaders = SqliteDatabase.defaultMaxReaders}) {
    return SqliteDatabaseImpl.withFactory(openFactory, maxReaders: maxReaders);
  }
}
