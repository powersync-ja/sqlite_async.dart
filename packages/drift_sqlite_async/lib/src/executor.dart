import 'dart:async';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';

// Ends with " RETURNING *", or starts with insert/update/delete.
// Drift-generated queries will always have the RETURNING *.
// The INSERT/UPDATE/DELETE check is for custom queries, and is not exhaustive.
final _returningCheck = RegExp(
    r'( RETURNING \*;?\s*$)|(^\s*(INSERT|UPDATE|DELETE))',
    caseSensitive: false);

class _SqliteAsyncDelegate extends _SqliteAsyncQueryDelegate
    implements DatabaseDelegate {
  final SqliteConnection db;
  bool _closed = false;
  bool _calledOpen = false;

  _SqliteAsyncDelegate(this.db) : super(db, db.writeLock);

  @override
  bool isInTransaction = false; // unused

  @override
  late final DbVersionDelegate versionDelegate =
      _SqliteAsyncVersionDelegate(db);

  // Not used - we override beginTransaction() with SqliteAsyncTransactionExecutor for more control.
  @override
  late final TransactionDelegate transactionDelegate =
      _SqliteAsyncTransactionDelegate(db);

  @override
  bool get isOpen => !db.closed && !_closed && _calledOpen;

  @override
  Future<void> open(QueryExecutorUser user) async {
    // Workaround - this ensures the db is open
    await db.get('SELECT 1');
    // We need to delay this until open() has been called, otherwise
    // migrations don't run.
    _calledOpen = true;
  }

  @override
  Future<void> close() async {
    // We don't own the underlying SqliteConnection - don't close it.
    _closed = true;
  }

  @override
  void notifyDatabaseOpened(OpeningDetails details) {
    // Unused
  }
}

class _SqliteAsyncQueryDelegate extends QueryDelegate {
  final SqliteWriteContext _context;
  final Future<T> Function<T>(
      Future<T> Function(SqliteWriteContext tx) callback)? _writeLock;

  _SqliteAsyncQueryDelegate(this._context, this._writeLock);

  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback) {
    if (_writeLock case var writeLock?) {
      return writeLock.call(callback);
    } else {
      return callback(_context);
    }
  }

  @override
  Future<void> runBatched(BatchedStatements statements) async {
    return writeLock((tx) async {
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
    return _context.execute(statement, args);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) async {
    return writeLock((tx) async {
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
      result = await _context.execute(statement, args);
    } else {
      // Plain SELECT statement - use getAll() to avoid using a write lock.
      result = await _context.getAll(statement, args);
    }
    return QueryResult(result.columnNames, result.rows);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    return writeLock((tx) async {
      await tx.execute(statement, args);
      final row = await tx.get('SELECT changes() as changes');
      return row['changes'];
    });
  }
}

class _SqliteAsyncTransactionDelegate extends SupportedTransactionDelegate {
  final SqliteConnection _db;

  _SqliteAsyncTransactionDelegate(this._db);

  @override
  FutureOr<void> Function(QueryDelegate, Future<void> Function(QueryDelegate))?
      get startNested => _startNested;

  @override
  Future<void> startTransaction(Future Function(QueryDelegate p1) run) async {
    await _startTransaction(_db, run);
  }

  Future<void> _startTransaction(
      SqliteWriteContext context, Future Function(QueryDelegate p1) run) async {
    await context.writeTransaction((context) async {
      final delegate = _SqliteAsyncQueryDelegate(context, null);
      return run(delegate);
    });
  }

  Future<void> _startNested(
      QueryDelegate outer, Future<void> Function(QueryDelegate) block) async {
    await _startTransaction(
        (outer as _SqliteAsyncQueryDelegate)._context, block);
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
  SqliteAsyncQueryExecutor(SqliteConnection db, {bool logStatements = false})
      : super(_SqliteAsyncDelegate(db), logStatements: logStatements);

  /// The underlying SqliteConnection used by drift to send queries.
  SqliteConnection get db {
    return (delegate as _SqliteAsyncDelegate).db;
  }

  @override
  bool get isSequential => false;
}
