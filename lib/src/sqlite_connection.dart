import 'dart:async';

import 'package:sqlite3/common.dart' as sqlite;
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/src/update_notification.dart';

/// Abstract class representing calls available in a read-only or read-write context.
abstract class SqliteReadContext {
  /// Execute a read-only (SELECT) query and return the results.
  Future<sqlite.ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]);

  /// Execute a read-only (SELECT) query and return a single result.
  Future<sqlite.Row> get(String sql, [List<Object?> parameters = const []]);

  /// Execute a read-only (SELECT) query and return a single optional result.
  Future<sqlite.Row?> getOptional(String sql,
      [List<Object?> parameters = const []]);

  /// For transactions, returns true if the lock is held (even if it has been
  /// rolled back).
  ///
  /// For database connections, returns true if the connection hasn't been closed
  /// yet.
  bool get closed;

  /// Returns true if auto-commit is enabled. This means the database is not
  /// currently in a transaction. This may be true even if a transaction lock
  /// is still held, when the transaction has been committed or rolled back.
  Future<bool> getAutoCommit();

  /// Run a function within a database isolate, with direct synchronous access
  /// to the underlying database.
  ///
  /// Using closures must be done with care, since values are sent over to the
  /// database isolate. To be safe, use this from a top-level function, taking
  /// only required arguments.
  ///
  /// The database may only be used within the callback, and only until the
  /// returned future returns. If it is used outside of that, it could cause
  /// unpredictable issues in other transactions.
  ///
  /// Example:
  ///
  /// ```dart
  /// Future<void> largeBatchInsert(SqliteConnection connection, List<List<Object>> rows) {
  ///   await connection.writeTransaction((tx) async {
  ///     await tx.computeWithDatabase((db) async {
  ///       final statement = db.prepare('INSERT INTO data(id, value) VALUES (?, ?)');
  ///       try {
  ///         for (var row in rows) {
  ///           statement.execute(row);
  ///         }
  ///       } finally {
  ///         statement.dispose();
  ///       }
  ///     });
  ///   });
  /// }
  /// ```
  Future<T> computeWithDatabase<T>(
      Future<T> Function(CommonDatabase db) compute);
}

/// Abstract class representing calls available in a read-write context.
abstract class SqliteWriteContext extends SqliteReadContext {
  /// Execute a write query (INSERT, UPDATE, DELETE) and return the results (if any).
  Future<sqlite.ResultSet> execute(String sql,
      [List<Object?> parameters = const []]);

  /// Execute a write query (INSERT, UPDATE, DELETE) multiple times with each
  /// parameter set. This is faster than executing separately with each
  /// parameter set.
  Future<void> executeBatch(String sql, List<List<Object?>> parameterSets);
}

/// Abstract class representing a connection to the SQLite database.
abstract class SqliteConnection extends SqliteWriteContext {
  /// Reports table change update notifications
  Stream<UpdateNotification>? get updates;

  /// Open a read-only transaction.
  ///
  /// Statements within the transaction must be done on the provided
  /// [SqliteReadContext] - attempting statements on the [SqliteConnection]
  /// instance will error.
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout});

  /// Open a read-write transaction.
  ///
  /// This takes a global lock - only one write transaction can execute against
  /// the database at a time. This applies even when constructing separate
  /// [SqliteDatabase] instances for the same database file.
  ///
  /// Statements within the transaction must be done on the provided
  /// [SqliteWriteContext] - attempting statements on the [SqliteConnection]
  /// instance will error.
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout});

  /// Execute a read query every time the source tables are modified.
  ///
  /// Use [throttle] to specify the minimum interval between queries.
  ///
  /// Source tables are automatically detected using `EXPLAIN QUERY PLAN`.
  Stream<sqlite.ResultSet> watch(String sql,
      {List<Object?> parameters = const [],
      Duration throttle = const Duration(milliseconds: 30)});

  /// Takes a read lock, without starting a transaction.
  ///
  /// The lock only applies to a single [SqliteConnection], and multiple
  /// connections may hold read locks at the same time.
  ///
  /// In most cases, [readTransaction] should be used instead.
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext});

  /// Takes a global lock, without starting a transaction.
  ///
  /// In most cases, [writeTransaction] should be used instead.
  ///
  /// The lock applies to all [SqliteConnection] instances for a [SqliteDatabase].
  /// Locks for separate [SqliteDatabase] instances on the same database file
  /// may be held concurrently.
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext});

  Future<void> close();

  /// Returns true if the connection is closed
  @override
  bool get closed;
}
