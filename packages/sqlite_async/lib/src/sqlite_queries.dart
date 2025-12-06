import 'package:sqlite3/common.dart' as sqlite;

import 'utils/shared_utils.dart';
import 'sqlite_connection.dart';
import 'update_notification.dart';

/// Mixin to provide default query functionality.
///
/// Classes using this need to implement [SqliteConnection.readLock]
/// and [SqliteConnection.writeLock].
mixin SqliteQueries implements SqliteWriteContext, SqliteConnection {
  @override
  Future<sqlite.ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return writeLock((ctx) async {
      return ctx.execute(sql, parameters);
    }, debugContext: 'execute()');
  }

  @override
  Future<sqlite.ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) {
    return readLock((ctx) async {
      return ctx.getAll(sql, parameters);
    }, debugContext: 'getAll()');
  }

  @override
  Future<sqlite.Row> get(String sql, [List<Object?> parameters = const []]) {
    return readLock((ctx) async {
      return ctx.get(sql, parameters);
    }, debugContext: 'get()');
  }

  @override
  Future<sqlite.Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) {
    return readLock((ctx) async {
      return ctx.getOptional(sql, parameters);
    }, debugContext: 'getOptional()');
  }

  @override
  Stream<sqlite.ResultSet> watch(String sql,
      {List<Object?> parameters = const [],
      Duration throttle = const Duration(milliseconds: 30),
      Iterable<String>? triggerOnTables}) {
    assert(updates != null,
        'updates stream must be provided to allow query watching');

    Stream<sqlite.ResultSet> watchInner(Iterable<String> trigger) {
      return onChange(
        trigger,
        throttle: throttle,
        triggerImmediately: true,
      ).asyncMap((_) => getAll(sql, parameters));
    }

    if (triggerOnTables case final knownTrigger?) {
      return watchInner(knownTrigger);
    } else {
      return Stream.fromFuture(getSourceTables(this, sql, parameters))
          .asyncExpand(watchInner);
    }
  }

  /// Create a Stream of changes to any of the specified tables.
  ///
  /// Example to get the same effect as [watch]:
  ///
  /// ```dart
  /// var subscription = db.onChange({'mytable'}).asyncMap((event) async {
  ///   var data = await db.getAll('SELECT * FROM mytable');
  ///   return data;
  /// }).listen((data) {
  ///   // Do something with the data here
  /// });
  /// ```
  ///
  /// This is preferred over [watch] when multiple queries need to be performed
  /// together when data is changed.
  Stream<UpdateNotification> onChange(Iterable<String>? tables,
      {Duration throttle = const Duration(milliseconds: 30),
      bool triggerImmediately = true}) {
    assert(updates != null,
        'updates stream must be provided to allow query watching');
    final filteredStream = tables != null
        ? updates!.transform(UpdateNotification.filterTablesTransformer(tables))
        : updates!;
    final throttledStream = UpdateNotification.throttleStream(
        filteredStream, throttle,
        addOne: triggerImmediately ? UpdateNotification.empty() : null);
    return throttledStream;
  }

  @override
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout}) async {
    return readLock((ctx) async {
      return await internalReadTransaction(ctx, callback);
    }, lockTimeout: lockTimeout, debugContext: 'readTransaction()');
  }

  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) async {
    return writeLock((ctx) async {
      return ctx.writeTransaction(callback);
    }, lockTimeout: lockTimeout, debugContext: 'writeTransaction()');
  }

  /// See [SqliteReadContext.computeWithDatabase].
  ///
  /// When called here directly on the connection, the call is wrapped in a
  /// write transaction.
  @override
  Future<T> computeWithDatabase<T>(
      Future<T> Function(sqlite.CommonDatabase db) compute) {
    return writeTransaction((tx) async {
      return tx.computeWithDatabase(compute);
    });
  }

  /// Execute a write query (INSERT, UPDATE, DELETE) multiple times with each
  /// parameter set. This is more faster than executing separately with each
  /// parameter set.
  ///
  /// When called here directly on the connection, the batch is wrapped in a
  /// write transaction.
  @override
  Future<void> executeBatch(String sql, List<List<Object?>> parameterSets) {
    return writeTransaction((tx) async {
      return tx.executeBatch(sql, parameterSets);
    });
  }

  @override
  Future<void> executeMultiple(String sql,
      [List<Object?> parameters = const []]) {
    return writeTransaction((tx) async {
      return tx.executeMultiple(sql, parameters);
    });
  }

  @override
  Future<void> refreshSchema() {
    return getAll("PRAGMA table_info('sqlite_master')");
  }
}
