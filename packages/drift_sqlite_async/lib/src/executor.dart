import 'dart:async';

import 'package:drift/backends.dart';
import 'package:drift_sqlite_async/src/transaction_executor.dart';
import 'package:sqlite_async/sqlite3.dart';
import 'package:sqlite_async/sqlite_async.dart';

class _SqliteAsyncDelegate extends DatabaseDelegate {
  final SqliteConnection db;
  bool _closed = false;

  _SqliteAsyncDelegate(this.db);

  @override
  late final DbVersionDelegate versionDelegate =
      _SqliteAsyncVersionDelegate(db);

  // Not used - we override beginTransaction() with SqliteAsyncTransactionExecutor for more control.
  @override
  late final TransactionDelegate transactionDelegate =
      const NoTransactionDelegate();

  @override
  bool get isOpen => !db.closed && !_closed;

  // Ends with " RETURNING *", or starts with insert/update/delete.
  // Drift-generated queries will always have the RETURNING *.
  // The INSERT/UPDATE/DELETE check is for custom queries, and is not exhaustive.
  final _returningCheck = RegExp(
      r'( RETURNING \*;?$)|(^(INSERT|UPDATE|DELETE))',
      caseSensitive: false);

  @override
  Future<void> open(QueryExecutorUser user) async {
    // Workaround - this ensures the db is open
    await db.get('SELECT 1');
  }

  @override
  Future<void> close() async {
    // We don't own the underlying SqliteConnection - don't close it.
    _closed = true;
  }

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    return db.writeLock((tx) async {
      // sqlite_async's batch functionality doesn't have enough flexibility to support
      // this with prepared statements yet.
      for (final arg in statements.arguments) {
        await tx.execute(
            statements.statements[arg.statementIndex], arg.arguments);
      }
    });
  }

  @override
  Future<void> runCustom(String statement, List<Object?> args) {
    return db.execute(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    return db.writeLock((tx) async {
      await tx.execute(statement, args);
      final row = await tx.get('SELECT last_insert_rowid() as row_id');
      return row['row_id'];
    });
  }

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async {
    ResultSet result;
    if (_returningCheck.hasMatch(statement)) {
      // Could be "INSERT INTO ... RETURNING *" (or update or delete),
      // so we need to use execute() instead of getAll().
      // This takes write lock, so we want to avoid it for plain select statements.
      // This is not an exhaustive check, but should cover all Drift-generated queries using
      // `runSelect()`.
      result = await db.execute(statement, args);
    } else {
      // Plain SELECT statement - use getAll() to avoid using a write lock.
      result = await db.getAll(statement, args);
    }
    return QueryResult(result.columnNames, result.rows);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    return db.writeLock((tx) async {
      await tx.execute(statement, args);
      final row = await tx.get('SELECT changes() as changes');
      return row['changes'];
    });
  }
}

class _SqliteAsyncVersionDelegate extends DynamicVersionDelegate {
  final SqliteConnection _db;

  _SqliteAsyncVersionDelegate(this._db);

  @override
  Future<int> get schemaVersion async {
    final result = await _db.get('PRAGMA user_version;');
    return result['user_version'];
  }

  @override
  Future<void> setSchemaVersion(int version) async {
    await _db.execute('PRAGMA user_version = $version;');
  }
}

/// A query executor that uses sqlite_async internally.
/// In most cases, SqliteAsyncConnection should be used instead, as it handles
/// stream queries automatically.
///
/// Wraps a sqlite_async [SqliteConnection] as a Drift [QueryExecutor].
///
/// The SqliteConnection must be instantiated before constructing this, and
/// is not closed when [SqliteAsyncQueryExecutor.close] is called.
///
/// This class handles delegating Drift's queries and transactions to the
/// [SqliteConnection].
///
/// Extnral update notifications from the [SqliteConnection] are _not_ forwarded
/// automatically - use [SqliteAsyncDriftConnection] for that.
class SqliteAsyncQueryExecutor extends DelegatedDatabase {
  SqliteAsyncQueryExecutor(SqliteConnection db)
      : super(
          _SqliteAsyncDelegate(db),
        );

  /// The underlying SqliteConnection used by drift to send queries.
  SqliteConnection get db {
    return (delegate as _SqliteAsyncDelegate).db;
  }

  @override
  bool get isSequential => false;

  @override
  TransactionExecutor beginTransaction() {
    return SqliteAsyncTransactionExecutor(db);
  }
}
