import 'dart:async';

import 'package:meta/meta.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/impl/single_connection_database.dart';
import 'package:sqlite_async/src/sqlite_options.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';

import '../impl/platform.dart' as platform;

/// A SQLite database instance.
///
/// Use one instance per database file. If multiple instances are used, update
/// notifications may not trigger, and calls may fail with "SQLITE_BUSY" errors.
abstract base class SqliteDatabase extends SqliteConnection {
  SqliteDatabase._();

  /// Open a SqliteDatabase.
  ///
  /// Only a single SqliteDatabase per [path] should be opened at a time.
  ///
  /// A connection pool is used by default, allowing multiple concurrent read
  /// transactions, and a single concurrent write transaction. Write transactions
  /// do not block read transactions, and read transactions will see the state
  /// from the last committed write transaction.
  factory SqliteDatabase(
      {required String path, SqliteOptions options = const SqliteOptions()}) {
    return SqliteDatabase.withFactory(
      SqliteOpenFactory(path: path, options: options),
    );
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
  factory SqliteDatabase.withFactory(SqliteOpenFactory openFactory) {
    return platform.openDatabaseWithFactory(openFactory);
  }

  /// Opens a [SqliteDatabase] that only wraps an underlying connection.
  ///
  /// This function may be useful in some instances like tests, but should not
  /// typically be used by applications. Compared to the other ways to open
  /// databases, it has the following downsides:
  ///
  ///  1. No connection pool / concurrent readers for native databases.
  ///  2. No reliable update notifications on the web.
  ///  3. There is no reliable transaction management in Dart, and opening the
  ///     same database with [SqliteDatabase.singleConnection] multiple times
  ///     may cause "database is locked" errors.
  ///
  /// Together with [SqliteConnection.synchronousWrapper], this can be used to
  /// open in-memory databases (e.g. via [SqliteOpenFactory.open]). That
  /// bypasses most convenience features, but may still be useful for
  /// short-lived databases used in tests.
  factory SqliteDatabase.singleConnection(SqliteConnection connection) {
    return SingleConnectionDatabase(connection);
  }

  /// Maximum number of concurrent read transactions.
  int get maxReaders;

  /// Factory that opens a raw database connection in each isolate.
  ///
  /// This must be safe to pass to different isolates.
  ///
  /// Use a custom class for this to customize the open process.
  SqliteOpenFactory get openFactory;

  @protected
  Future<void> get isInitialized;

  /// Wait for initialization to complete.
  ///
  /// While initializing is automatic, this helps to catch and report initialization errors.
  Future<void> initialize() async {
    await isInitialized;
  }

  /// Locks all underlying connections making up this database, and gives [block] access to all of them at once.
  /// This can be useful to run the same statement on all connections. For instance,
  /// ATTACHing a database, that is expected to be available in all connections.
  Future<T> withAllConnections<T>(
      Future<T> Function(
              SqliteWriteContext writer, List<SqliteReadContext> readers)
          block);
}

/// Internal superclass for all [SqliteDatabase] implementations.
@internal
abstract base class SqliteDatabaseImpl extends SqliteDatabase {
  SqliteDatabaseImpl() : super._();
}
