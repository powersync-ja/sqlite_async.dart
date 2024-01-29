import 'dart:async';
import 'package:meta/meta.dart';
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
    return mutex.lock(() => callback(WebReadContext(executor!)));
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    await isInitialized;
    return mutex.lock(() => callback(WebWriteContext(executor!)));
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
