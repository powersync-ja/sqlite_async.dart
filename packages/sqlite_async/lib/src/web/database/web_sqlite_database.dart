import 'dart:async';
import 'package:meta/meta.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/common/mutex.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
import 'package:sqlite_async/src/web/web_isolate_connection_factory.dart';
import 'package:sqlite_async/src/common/sqlite_database.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_options.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:sqlite_async/src/web/web_mutex.dart';
import 'package:sqlite_async/src/web/web_sqlite_open_factory.dart';
import 'package:sqlite_async/web.dart';

import '../database.dart';

/// Web implementation of [SqliteDatabase]
/// Uses a web worker for SQLite connection
class SqliteDatabaseImpl
    with SqliteQueries, SqliteDatabaseMixin
    implements SqliteDatabase, WebSqliteConnection {
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
  int maxReaders;

  @override
  @protected
  late Future<void> isInitialized;

  @override
  AbstractDefaultSqliteOpenFactory openFactory;

  late final Mutex mutex;
  late final WebDatabase _connection;
  StreamSubscription? _broadcastUpdatesSubscription;

  /// Open a SqliteDatabase.
  ///
  /// Only a single SqliteDatabase per [path] should be opened at a time.
  ///
  /// A connection pool is used by default, allowing multiple concurrent read
  /// transactions, and a single concurrent write transaction. Write transactions
  /// do not block read transactions, and read transactions will see the state
  /// from the last committed write transaction.
  ///
  /// A maximum of [maxReaders] concurrent read transactions are allowed.
  factory SqliteDatabaseImpl(
      {required path,
      int maxReaders = SqliteDatabase.defaultMaxReaders,
      SqliteOptions options = const SqliteOptions.defaults()}) {
    final factory =
        DefaultSqliteOpenFactory(path: path, sqliteOptions: options);
    return SqliteDatabaseImpl.withFactory(factory, maxReaders: maxReaders);
  }

  /// Advanced: Open a database with a specified factory.
  ///
  /// The factory is used to open each database connection in background isolates.
  ///
  /// Use when control is required over the opening process. Examples include:
  ///  1. Specifying the path to `libsqlite.so` on Linux.
  ///  2. Running additional per-connection PRAGMA statements on each connection.
  ///  3. Creating custom SQLite functions.
  ///  4. Creating temporary views or triggers.
  SqliteDatabaseImpl.withFactory(this.openFactory,
      {this.maxReaders = SqliteDatabase.defaultMaxReaders}) {
    mutex = MutexImpl();
    // This way the `updates` member is available synchronously
    updates = updatesController.stream;
    isInitialized = _init();
  }

  Future<void> _init() async {
    _connection = await openFactory.openConnection(SqliteOpenOptions(
        primaryConnection: true, readOnly: false, mutex: mutex)) as WebDatabase;

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
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    await isInitialized;
    return _runZoned(() {
      return _connection.readLock(callback,
          lockTimeout: lockTimeout, debugContext: debugContext);
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
  IsolateConnectionFactoryImpl isolateConnectionFactory() {
    throw UnimplementedError();
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
}
