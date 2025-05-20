import 'dart:async';

import 'package:sqlite_async/sqlite3_wasm.dart';

/// Wrap a CommonDatabase to throttle its updates stream.
/// This is so that we can throttle the updates _within_
/// the worker process, avoiding mass notifications over
/// the MessagePort.
class ThrottledCommonDatabase extends CommonDatabase {
  final CommonDatabase _db;
  final StreamController<bool> _transactionController =
      StreamController.broadcast();

  ThrottledCommonDatabase(this._db);

  @override
  int get userVersion => _db.userVersion;

  @override
  set userVersion(int userVersion) {
    _db.userVersion = userVersion;
  }

  @override
  bool get autocommit => _db.autocommit;

  @override
  DatabaseConfig get config => _db.config;

  @override
  void createAggregateFunction<V>(
      {required String functionName,
      required AggregateFunction<V> function,
      AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
      bool deterministic = false,
      bool directOnly = true}) {
    _db.createAggregateFunction(functionName: functionName, function: function);
  }

  @override
  void createCollation(
      {required String name, required CollatingFunction function}) {
    _db.createCollation(name: name, function: function);
  }

  @override
  void createFunction(
      {required String functionName,
      required ScalarFunction function,
      AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
      bool deterministic = false,
      bool directOnly = true}) {
    _db.createFunction(functionName: functionName, function: function);
  }

  @override
  void dispose() {
    _db.dispose();
  }

  @override
  void execute(String sql, [List<Object?> parameters = const []]) {
    _db.execute(sql, parameters);
  }

  @override
  int getUpdatedRows() {
    // ignore: deprecated_member_use
    return _db.getUpdatedRows();
  }

  @override
  int get lastInsertRowId => _db.lastInsertRowId;

  @override
  CommonPreparedStatement prepare(String sql,
      {bool persistent = false, bool vtab = true, bool checkNoTail = false}) {
    return _db.prepare(sql,
        persistent: persistent, vtab: vtab, checkNoTail: checkNoTail);
  }

  @override
  List<CommonPreparedStatement> prepareMultiple(String sql,
      {bool persistent = false, bool vtab = true}) {
    return _db.prepareMultiple(sql, persistent: persistent, vtab: vtab);
  }

  @override
  ResultSet select(String sql, [List<Object?> parameters = const []]) {
    bool preAutocommit = _db.autocommit;
    final result = _db.select(sql, parameters);
    bool postAutocommit = _db.autocommit;
    if (!preAutocommit && postAutocommit) {
      _transactionController.add(true);
    }
    return result;
  }

  @override
  int get updatedRows => _db.updatedRows;

  @override
  Stream<SqliteUpdate> get updates {
    return throttledUpdates(_db, _transactionController.stream);
  }

  @override
  VoidPredicate? get commitFilter => _db.commitFilter;

  @override
  set commitFilter(VoidPredicate? filter) => _db.commitFilter = filter;

  @override
  Stream<void> get commits => _db.commits;

  @override
  Stream<void> get rollbacks => _db.rollbacks;
}

/// This throttles the database update stream to:
/// 1. Trigger max once every 1ms.
/// 2. Only trigger _after_ transactions.
Stream<SqliteUpdate> throttledUpdates(
    CommonDatabase source, Stream transactionStream) {
  StreamController<SqliteUpdate>? controller;
  Set<SqliteUpdate> pendingUpdates = {};
  var paused = false;

  Timer? updateDebouncer;

  void maybeFireUpdates() {
    updateDebouncer?.cancel();
    updateDebouncer = null;

    if (paused) {
      // Continue collecting updates, but don't fire any
      return;
    }

    if (!source.autocommit) {
      // Inside a transaction - do not fire updates
      return;
    }

    if (pendingUpdates.isNotEmpty) {
      for (var update in pendingUpdates) {
        controller!.add(update);
      }

      pendingUpdates.clear();
    }
  }

  void collectUpdate(SqliteUpdate event) {
    // We merge updates with the same kind and tableName.
    // rowId is never used in sqlite_async.
    pendingUpdates.add(SqliteUpdate(event.kind, event.tableName, 0));

    updateDebouncer ??=
        Timer(const Duration(milliseconds: 1), maybeFireUpdates);
  }

  StreamSubscription? txSubscription;
  StreamSubscription? sourceSubscription;

  controller = StreamController(onListen: () {
    txSubscription = transactionStream.listen((event) {
      maybeFireUpdates();
    }, onError: (error) {
      controller?.addError(error);
    });

    sourceSubscription = source.updates.listen(collectUpdate, onError: (error) {
      controller?.addError(error);
    });
  }, onPause: () {
    paused = true;
  }, onResume: () {
    paused = false;
    maybeFireUpdates();
  }, onCancel: () {
    txSubscription?.cancel();
    sourceSubscription?.cancel();
  });

  return controller.stream;
}
