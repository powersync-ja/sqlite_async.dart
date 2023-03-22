import 'package:sqlite3/sqlite3.dart' as sqlite;

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
      Future<T> Function(sqlite.Database db) compute);
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
  /// the database at a time.
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
  /// In most cases, [readTransaction] should be used instead.
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout});

  /// Takes a global lock, without starting a transaction.
  ///
  /// In most cases, [writeTransaction] should be used instead.
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout});

  Future<void> close();
}
