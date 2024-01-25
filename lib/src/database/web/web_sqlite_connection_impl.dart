import 'dart:async';
import 'package:meta/meta.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:mutex/mutex.dart';
import 'package:sqlite_async/src/database/web/executor/sqlite_executor.dart';
import 'package:sqlite_async/src/database/web/web_db_context.dart';
import 'package:sqlite_async/src/open_factory/web/web_sqlite_open_factory_impl.dart';

class WebSqliteConnectionImpl with SqliteQueries implements SqliteConnection {
  @override
  bool get closed {
    return executor == null || executor!.closed;
  }

  @override
  late Stream<UpdateNotification> updates;

  late final Mutex mutex;
  DefaultSqliteOpenFactoryImplementation openFactory;

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
    return mutex.protect(() => callback(WebReadContext(executor!)));
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    await isInitialized;
    return mutex.protect(() => callback(WebWriteContext(executor!)));
  }

  @override
  Future<void> close() async {
    await isInitialized;
    await executor!.close();
  }
}
