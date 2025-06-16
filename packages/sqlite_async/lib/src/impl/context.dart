import 'package:sqlite3/common.dart';

import '../sqlite_connection.dart';

abstract base class UnscopedContext implements SqliteReadContext {
  Future<ResultSet> execute(String sql, List<Object?> parameters);
  Future<void> executeBatch(String sql, List<List<Object?>> parameterSets);

  /// Returns an [UnscopedContext] useful as the outermost transaction.
  ///
  /// This is called by [ScopedWriteContext.writeTransaction] _after_ executing
  /// the first `BEGIN` statement.
  /// This is used on the web to assert that the auto-commit state is false
  /// before running statements.
  UnscopedContext interceptOutermostTransaction() {
    return this;
  }
}

final class ScopedReadContext implements SqliteReadContext {
  final UnscopedContext _context;

  /// Whether this context view is locked on an inner operation like a
  /// transaction.
  ///
  /// We don't use a mutex because we don't want to serialize access - we just
  /// want to forbid concurrent operations.
  bool _isLocked = false;

  /// Whether this particular view of a read context has been closed, e.g.
  /// because the callback owning it has returned.
  bool _closed = false;

  ScopedReadContext(this._context);

  void _checkNotLocked() {
    _checkStillOpen();

    if (_isLocked) {
      throw StateError(
          'The context from the callback was locked, e.g. due to a nested '
          'transaction.');
    }
  }

  void _checkStillOpen() {
    if (_closed) {
      throw StateError('This context to a callback is no longer open. '
          'Make sure to await all statements on a database to avoid a context '
          'still being used after its callback has finished.');
    }
  }

  @override
  bool get closed => _closed || _context.closed;

  @override
  Future<R> computeWithDatabase<R>(
      Future<R> Function(CommonDatabase db) compute) async {
    _checkNotLocked();
    return await _context.computeWithDatabase(compute);
  }

  @override
  Future<Row> get(String sql, [List<Object?> parameters = const []]) async {
    _checkNotLocked();
    final rows = await getAll(sql, parameters);
    return rows.first;
  }

  @override
  Future<ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) async {
    _checkNotLocked();
    return await _context.getAll(sql, parameters);
  }

  @override
  Future<bool> getAutoCommit() async {
    _checkStillOpen();
    return _context.getAutoCommit();
  }

  @override
  Future<Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) async {
    _checkNotLocked();
    final rows = await getAll(sql, parameters);
    return rows.firstOrNull;
  }

  void invalidate() => _closed = true;

  static Future<T> assumeReadLock<T>(
    UnscopedContext unsafe,
    Future<T> Function(SqliteReadContext) callback,
  ) async {
    final scoped = ScopedReadContext(unsafe);
    try {
      return await callback(scoped);
    } finally {
      scoped.invalidate();
    }
  }
}

final class ScopedWriteContext extends ScopedReadContext
    implements SqliteWriteContext {
  /// The "depth" of virtual nested transaction.
  ///
  /// A value of `0` indicates that this is operating outside of a transaction.
  /// A value of `1` indicates a regular transaction (guarded with `BEGIN` and
  /// `COMMIT` statements).
  /// All higher values indicate a nested transaction implemented with
  /// savepoint statements.
  final int transactionDepth;

  ScopedWriteContext(super._context, {this.transactionDepth = 0});

  @override
  Future<ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    _checkNotLocked();
    return await _context.execute(sql, parameters);
  }

  @override
  Future<void> executeBatch(
      String sql, List<List<Object?>> parameterSets) async {
    _checkNotLocked();

    return await _context.executeBatch(sql, parameterSets);
  }

  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback) async {
    _checkNotLocked();
    final (begin, commit, rollback) = _beginCommitRollback(transactionDepth);
    ScopedWriteContext? inner;

    final innerContext = transactionDepth == 0
        ? _context.interceptOutermostTransaction()
        : _context;

    try {
      _isLocked = true;

      await _context.execute(begin, const []);

      inner = ScopedWriteContext(innerContext,
          transactionDepth: transactionDepth + 1);
      final result = await callback(inner);
      await innerContext.execute(commit, const []);
      return result;
    } catch (e) {
      try {
        await innerContext.execute(rollback, const []);
      } catch (e) {
        // In rare cases, a ROLLBACK may fail.
        // Safe to ignore.
      }
      rethrow;
    } finally {
      _isLocked = false;
      inner?.invalidate();
    }
  }

  static (String, String, String) _beginCommitRollback(int level) {
    return switch (level) {
      0 => ('BEGIN IMMEDIATE', 'COMMIT', 'ROLLBACK'),
      final nested => (
          'SAVEPOINT s$nested',
          'RELEASE s$nested',
          'ROLLBACK TO s$nested'
        )
    };
  }

  static Future<T> assumeWriteLock<T>(
    UnscopedContext unsafe,
    Future<T> Function(SqliteWriteContext) callback,
  ) async {
    final scoped = ScopedWriteContext(unsafe);
    try {
      return await callback(scoped);
    } finally {
      scoped.invalidate();
    }
  }
}
