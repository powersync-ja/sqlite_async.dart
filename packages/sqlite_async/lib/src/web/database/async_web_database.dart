import 'dart:async';
import 'package:meta/meta.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/common/mutex.dart';
import 'package:sqlite_async/src/common/sqlite_database.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:sqlite_async/web.dart' hide WebDatabaseEndpoint;

import '../connection.dart';
import '../database.dart';

/// A [SqliteDatabase] implemented by delegating to a [WebDatabase] opened
/// asynchronously.
final class AsyncWebDatabaseImpl extends SqliteDatabaseImpl
    implements WebSqliteConnection {
  @override
  bool get closed {
    return _connection.closed;
  }

  @override
  Future<void> get closedFuture => _connection.closedFuture;

  final StreamController<UpdateNotification> updatesController =
      StreamController.broadcast();

  @override
  late Stream<UpdateNotification> updates;

  @override
  int get maxReaders => 0;

  @override
  @protected
  late Future<void> isInitialized;

  @override
  WebSqliteOpenFactory openFactory;

  late final WebDatabase _connection;
  StreamSubscription? _broadcastUpdatesSubscription;

  AsyncWebDatabaseImpl(this.openFactory) {
    // This way the `updates` member is available synchronously
    updates = updatesController.stream;
    isInitialized = _init();
  }

  Future<void> _init() async {
    _connection = await openFactory.openConnection(
        SqliteOpenOptions(primaryConnection: true, readOnly: false));

    final broadcastUpdates = _connection.broadcastUpdates;
    if (broadcastUpdates == null) {
      // We can use updates directly from the database.
      _connection.updates.forEach((update) {
        updatesController.add(update);
      });
    } else {
      _connection.updates.forEach((update) {
        updatesController.add(update);

        // Share local updates with other tabs
        broadcastUpdates.send(update);
      });

      // Also add updates from other tabs, note that things we send aren't
      // received by our tab.
      _broadcastUpdatesSubscription =
          broadcastUpdates.updates.listen((updates) {
        updatesController.add(updates);
      });
    }
  }

  T _runZoned<T>(T Function() callback, {required String debugContext}) {
    if (Zone.current[this] != null) {
      throw LockError(
          'Recursive lock is not allowed. Use `tx.$debugContext` instead of `db.$debugContext`.');
    }
    var zone = Zone.current.fork(zoneValues: {this: true});
    return zone.run(callback);
  }

  @override
  Future<T> abortableReadLock<T>(
      Future<T> Function(SqliteReadContext tx) callback,
      {Future<void>? abortTrigger,
      String? debugContext}) async {
    await isInitialized;
    return _runZoned(() {
      return _connection.abortableReadLock(callback,
          abortTrigger: abortTrigger, debugContext: debugContext);
    }, debugContext: debugContext ?? 'execute()');
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext, bool? flush}) async {
    await isInitialized;
    return _runZoned(() {
      return _connection.writeLock(callback,
          lockTimeout: lockTimeout, debugContext: debugContext, flush: flush);
    }, debugContext: debugContext ?? 'execute()');
  }

  @override
  Future<T> abortableWriteLock<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Future<void>? abortTrigger,
      String? debugContext,
      bool? flush}) async {
    await isInitialized;
    return _runZoned(() {
      return _connection.abortableWriteLock(callback,
          abortTrigger: abortTrigger, debugContext: debugContext, flush: flush);
    }, debugContext: debugContext ?? 'execute()');
  }

  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout,
      bool? flush}) async {
    await isInitialized;
    return _runZoned(
        () => _connection.writeTransaction(callback,
            lockTimeout: lockTimeout, flush: flush),
        debugContext: 'writeTransaction()');
  }

  @override
  Future<void> flush() async {
    await isInitialized;
    return _connection.flush();
  }

  @override
  Future<void> close() async {
    await isInitialized;
    _broadcastUpdatesSubscription?.cancel();
    updatesController.close();
    return _connection.close();
  }

  @override
  Future<bool> getAutoCommit() async {
    await isInitialized;
    return _connection.getAutoCommit();
  }

  @override
  Future<WebDatabaseEndpoint> exposeEndpoint() async {
    return await _connection.exposeEndpoint();
  }

  @override
  Future<T> withAllConnections<T>(
      Future<T> Function(
              SqliteWriteContext writer, List<SqliteReadContext> readers)
          block) {
    return writeLock((_) => block(_connection, []));
  }
}
