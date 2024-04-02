import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'database_utils.dart';
import 'sqlite_connection.dart';
import 'update_notification.dart';

/// Mixin to provide default query functionality.
///
/// Classes using this need to implement [SqliteConnection.lock].
mixin SqliteQueries implements SqliteWriteContext, SqliteConnection {
  /// Broadcast stream that is notified of any table updates
  Stream<UpdateNotification>? get updates;

  @override
  Future<sqlite.ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return lock((ctx) async {
      return ctx.execute(sql, parameters);
    }, debugContext: 'execute()');
  }

  @override
  Future<sqlite.ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) {
    return lock((ctx) async {
      return ctx.getAll(sql, parameters);
    }, readOnly: true, debugContext: 'getAll()');
  }

  @override
  Future<sqlite.Row> get(String sql, [List<Object?> parameters = const []]) {
    return lock((ctx) async {
      return ctx.get(sql, parameters);
    }, readOnly: true, debugContext: 'get()');
  }

  @override
  Future<sqlite.Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) {
    return lock((ctx) async {
      return ctx.getOptional(sql, parameters);
    }, readOnly: true, debugContext: 'getOptional()');
  }

  @override
  Stream<sqlite.ResultSet> watch(String sql,
      {List<Object?> parameters = const [],
      Duration throttle = const Duration(milliseconds: 30),
      Iterable<String>? triggerOnTables}) async* {
    assert(updates != null,
        'updates stream must be provided to allow query watching');
    final tables =
        triggerOnTables ?? await getSourceTables(this, sql, parameters);
    final filteredStream =
        updates!.transform(UpdateNotification.filterTablesTransformer(tables));
    final throttledStream = UpdateNotification.throttleStream(
        filteredStream, throttle,
        addOne: UpdateNotification.empty());

    // FIXME:
    // When the subscription is cancelled, this performs a final query on the next
    // update.
    // The loop only stops once the "yield" is reached.
    // Using asyncMap instead of a generator would solve it, but then the body
    // here can't be async for getSourceTables().
    await for (var _ in throttledStream) {
      yield await getAll(sql, parameters);
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
    // ignore: deprecated_member_use_from_same_package
    return readLock((ctx) async {
      return await internalReadTransaction(ctx, callback);
    }, lockTimeout: lockTimeout, debugContext: 'readTransaction()');
  }

  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) async {
    // ignore: deprecated_member_use_from_same_package
    return writeLock((ctx) async {
      return await internalWriteTransaction(ctx, callback);
    }, lockTimeout: lockTimeout, debugContext: 'writeTransaction()');
  }

  /// See [SqliteReadContext.computeWithDatabase].
  ///
  /// When called here directly on the connection, the call is wrapped in a
  /// write transaction.
  @override
  Future<T> computeWithDatabase<T>(
      Future<T> Function(sqlite.Database db) compute) {
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
  Future<T> lock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {bool? readOnly, Duration? lockTimeout, String? debugContext}) {
    if (readOnly == true) {
      // ignore: deprecated_member_use_from_same_package
      return readLock((ctx) => callback(ctx as SqliteWriteContext),
          lockTimeout: lockTimeout, debugContext: debugContext);
    } else {
      // ignore: deprecated_member_use_from_same_package
      return writeLock(callback,
          lockTimeout: lockTimeout, debugContext: debugContext);
    }
  }

  @override
  Future<T> transaction<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {bool? readOnly, Duration? lockTimeout}) {
    if (readOnly == true) {
      // ignore: deprecated_member_use_from_same_package
      return readTransaction((ctx) => callback(ctx as SqliteWriteContext),
          lockTimeout: lockTimeout);
    } else {
      // Uses connection-level lock, unlike writeTransaction which uses a
      // database-level lock.
      return lock((ctx) async {
        return await internalWriteTransaction(ctx, callback);
      }, lockTimeout: lockTimeout, debugContext: 'writeTransaction()');
    }
  }
}
