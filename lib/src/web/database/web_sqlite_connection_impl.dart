import 'dart:async';
import 'package:meta/meta.dart';
import 'package:sqlite_async/src/common/abstract_mutex.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';

import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:sqlite_async/src/web/web_mutex.dart';
import 'package:sqlite_async/src/web/web_sqlite_open_factory.dart';

import 'executor/sqlite_executor.dart';
import 'web_db_context.dart';

class WebSqliteConnectionImpl with SqliteQueries implements SqliteConnection {
  @override
  bool get closed {
    return executor == null || executor!.closed;
  }

  @override
  late Stream<UpdateNotification> updates;

  late final Mutex mutex;
  DefaultSqliteOpenFactory openFactory;

  @protected
  final StreamController<UpdateNotification> updatesController =
      StreamController.broadcast();

  @protected
  late SQLExecutor? executor;

  @protected
  late Future<void> isInitialized;

  WebSqliteConnectionImpl({required this.openFactory, required this.mutex}) {
    updates = updatesController.stream;
    isInitialized = _init();
  }

  Future<void> _init() async {
    executor = await openFactory.openExecutor(
        SqliteOpenOptions(primaryConnection: true, readOnly: false));

    executor!.updateStream.forEach((tables) {
      updatesController.add(UpdateNotification(tables));
    });
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    await isInitialized;
    return _runZoned(
        () => mutex.lock(() => callback(WebReadContext(executor!)),
            timeout: lockTimeout),
        debugContext: debugContext ?? 'execute()');
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    await isInitialized;
    return _runZoned(
        () => mutex.lock(() => callback(WebWriteContext(executor!)),
            timeout: lockTimeout),
        debugContext: debugContext ?? 'execute()');
  }

  /// The [Mutex] on individual connections do already error in recursive locks.
  ///
  /// We duplicate the same check here, to:
  /// 1. Also error when the recursive transaction is handled by a different
  ///    connection (with a different lock).
  /// 2. Give a more specific error message when it happens.
  T _runZoned<T>(T Function() callback, {required String debugContext}) {
    if (Zone.current[this] != null) {
      throw LockError(
          'Recursive lock is not allowed. Use `tx.$debugContext` instead of `db.$debugContext`.');
    }
    var zone = Zone.current.fork(zoneValues: {this: true});
    return zone.run(callback);
  }

  @override
  Future<void> close() async {
    await isInitialized;
    await executor!.close();
  }

  @override
  Future<bool> getAutoCommit() {
    throw UnimplementedError();
  }
}
