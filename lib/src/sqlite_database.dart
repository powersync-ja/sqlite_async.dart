import 'dart:async';
import 'dart:isolate';

import 'connection_pool.dart';
import 'isolate_completer.dart';
import 'mutex.dart';
import 'sqlite_connection.dart';
import 'sqlite_connection_impl.dart';
import 'sqlite_open_factory.dart';
import 'sqlite_options.dart';
import 'sqlite_queries.dart';
import 'update_notification.dart';

/// A managed database.
///
/// Use one instance per database file.
///
/// Use [SqliteDatabase.connect] to connect to the PowerSync service,
/// to keep the local database in sync with the remote database.
class SqliteDatabase with SqliteQueries implements SqliteConnection {
  /// Maximum number of concurrent read transactions.
  final int maxReaders;

  /// Global lock to serialize write transactions.
  final Mutex mutex = Mutex();

  /// Factory that opens a raw database connection in each isolate.
  ///
  /// This must be safe to pass to different isolates.
  ///
  /// Use a custom class for this to customize the open process.
  final SqliteOpenFactory openFactory;

  /// Use this stream to subscribe to notifications of updates to tables.
  @override
  late final Stream<UpdateNotification> updates;

  final StreamController<UpdateNotification> _updatesController =
      StreamController.broadcast();

  final ReceivePort _eventsPort = ReceivePort();

  late final SqliteConnectionImpl _internalConnection;
  late final SqliteConnectionPool _pool;
  late final Future<void> _initialized;

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
  ///
  /// Advanced: Use [sqliteSetup] to execute custom initialization logic in
  /// each database isolate.
  factory SqliteDatabase(
      {required path,
      maxReaders = 5,
      options = const SqliteOptions.defaults()}) {
    final factory =
        DefaultSqliteOpenFactory(path: path, sqliteOptions: options);
    return SqliteDatabase.withFactory(openFactory: factory);
  }

  /// Advanced: Open a database with a specified factory.
  ///
  /// Use when control is required over the opening process.
  SqliteDatabase.withFactory({required this.openFactory, this.maxReaders = 5}) {
    updates = _updatesController.stream;
    _internalConnection = _openPrimaryConnection(debugName: 'sqlite-writer');
    _pool = SqliteConnectionPool(openFactory,
        upstreamPort: _eventsPort.sendPort,
        updates: updates,
        writeConnection: _internalConnection,
        debugName: 'sqlite',
        maxReaders: maxReaders,
        mutex: mutex);

    _listenForEvents();

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

  void _listenForEvents() {
    UpdateNotification? updates;

    _eventsPort.listen((message) async {
      if (message is List) {
        String type = message[0];
        if (type == 'update') {
          Set<String> tables = message[1];
          if (updates == null) {
            updates = UpdateNotification(tables);
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
            updates!.tables.addAll(tables);
          }
        } else if (type == 'init-db') {
          PortCompleter<void> completer = message[1];
          await completer.handle(() async {
            await _initialized;
          });
        }
      }
    });
  }

  SqliteConnectionImpl _openPrimaryConnection({String? debugName}) {
    return SqliteConnectionImpl(
        upstreamPort: _eventsPort.sendPort,
        primary: true,
        updates: updates,
        debugName: debugName,
        mutex: mutex,
        readOnly: false,
        openFactory: openFactory);
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
      {Duration? lockTimeout}) {
    return _pool.readLock(callback, lockTimeout: lockTimeout);
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) {
    return _pool.writeLock(callback, lockTimeout: lockTimeout);
  }
}
