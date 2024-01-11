import 'dart:async';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import '../../../mutex.dart';
import '../../utils/database_utils.dart';
import '../../sqlite_connection.dart';
import '../../open_factory/native/native_sqlite_open_factory.dart';
import '../../open_factory/abstract_open_factory.dart';
import '../../sqlite_options.dart';
import '../../update_notification.dart';
import '../abstract_sqlite_database.dart';
import 'port_channel.dart';
import 'connection_pool.dart';
import 'sqlite_connection_impl.dart';
import '../../isolate_connection_factory/web/native_isolate_connection_factory.dart';

/// A SQLite database instance.
///
/// Use one instance per database file. If multiple instances are used, update
/// notifications may not trigger, and calls may fail with "SQLITE_BUSY" errors.
class SqliteDatabase extends AbstractSqliteDatabase {
  /// Use this stream to subscribe to notifications of updates to tables.
  @override
  late final Stream<UpdateNotification> updates;

  final AbstractDefaultSqliteOpenFactory<Database> openFactory;

  final StreamController<UpdateNotification> _updatesController =
      StreamController.broadcast();

  late final PortServer _eventsPort;

  late final SqliteConnectionImpl _internalConnection;
  late final SqliteConnectionPool _pool;
  late final Future<void> _initialized;

  /// Global lock to serialize write transactions.
  final SimpleMutex mutex = SimpleMutex();

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
  factory SqliteDatabase(
      {required path,
      int maxReaders = AbstractSqliteDatabase.defaultMaxReaders,
      SqliteOptions options = const SqliteOptions.defaults()}) {
    final factory =
        DefaultSqliteOpenFactory(path: path, sqliteOptions: options);
    return SqliteDatabase.withFactory(factory, maxReaders: maxReaders);
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
  SqliteDatabase.withFactory(this.openFactory,
      {int maxReaders = AbstractSqliteDatabase.defaultMaxReaders}) {
    updates = _updatesController.stream;

    super.maxReaders = maxReaders;

    _listenForEvents();

    _internalConnection = _openPrimaryConnection(debugName: 'sqlite-writer');
    _pool = SqliteConnectionPool(openFactory,
        upstreamPort: _eventsPort.client(),
        updates: updates,
        writeConnection: _internalConnection,
        debugName: 'sqlite',
        maxReaders: maxReaders,
        mutex: mutex);

    _initialized = _init();
  }

  Future<void> _init() async {
    await _internalConnection.ready;
  }

  /// Wait for initialization to complete.
  ///
  /// While initializing is automatic, this helps to catch and report initialization errors.
  Future<void> initialize() async {
    await _initialized;
  }

  @override
  bool get closed {
    return _pool.closed;
  }

  void _listenForEvents() {
    UpdateNotification? updates;

    Map<SendPort, StreamSubscription> subscriptions = {};

    _eventsPort = PortServer((message) async {
      if (message is UpdateNotification) {
        if (updates == null) {
          updates = message;
          // Use the mutex to only send updates after the current transaction.
          // Do take care to avoid getting a lock for each individual update -
          // that could add massive performance overhead.
          mutex.lock(() async {
            if (updates != null) {
              _updatesController.add(updates!);
              updates = null;
            }
          });
        } else {
          updates!.tables.addAll(message.tables);
        }
        return null;
      } else if (message is InitDb) {
        await _initialized;
        return null;
      } else if (message is SubscribeToUpdates) {
        if (subscriptions.containsKey(message.port)) {
          return;
        }
        final subscription = _updatesController.stream.listen((event) {
          message.port.send(event);
        });
        subscriptions[message.port] = subscription;
        return null;
      } else if (message is UnsubscribeToUpdates) {
        final subscription = subscriptions.remove(message.port);
        subscription?.cancel();
        return null;
      } else {
        throw ArgumentError('Unknown message type: $message');
      }
    });
  }

  /// A connection factory that can be passed to different isolates.
  ///
  /// Use this to access the database in background isolates.
  IsolateConnectionFactory isolateConnectionFactory() {
    return IsolateConnectionFactory(
        openFactory: openFactory,
        mutex: mutex.shared,
        upstreamPort: _eventsPort.client());
  }

  SqliteConnectionImpl _openPrimaryConnection({String? debugName}) {
    return SqliteConnectionImpl(
        upstreamPort: _eventsPort.client(),
        primary: true,
        updates: updates,
        debugName: debugName,
        mutex: mutex,
        readOnly: false,
        openFactory: openFactory);
  }

  @override
  Future<void> close() async {
    await _pool.close();
    _updatesController.close();
    _eventsPort.close();
    await mutex.close();
  }

  /// Open a read-only transaction.
  ///
  /// Up to [maxReaders] read transactions can run concurrently.
  /// After that, read transactions are queued.
  ///
  /// Read transactions can run concurrently to a write transaction.
  ///
  /// Changes from any write transaction are not visible to read transactions
  /// started before it.
  @override
  Future<T> readTransaction<T>(
      Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout}) {
    return _pool.readTransaction(callback, lockTimeout: lockTimeout);
  }

  /// Open a read-write transaction.
  ///
  /// Only a single write transaction can run at a time - any concurrent
  /// transactions are queued.
  ///
  /// The write transaction is automatically committed when the callback finishes,
  /// or rolled back on any error.
  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) {
    return _pool.writeTransaction(callback, lockTimeout: lockTimeout);
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    return _pool.readLock(callback,
        lockTimeout: lockTimeout, debugContext: debugContext);
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    return _pool.writeLock(callback,
        lockTimeout: lockTimeout, debugContext: debugContext);
  }
}
