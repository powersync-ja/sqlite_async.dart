import 'dart:async';
import 'package:mutex/mutex.dart';

import 'package:sqlite_async/src/common/abstract_sqlite_database.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/web/web_isolate_connection_factory.dart';
import 'package:sqlite_async/src/web/web_sqlite_open_factory.dart';
import 'package:sqlite_async/src/sqlite_options.dart';
import 'package:sqlite_async/src/update_notification.dart';

import 'web_sqlite_connection_impl.dart';

class SqliteDatabase extends AbstractSqliteDatabase {
  @override
  bool get closed {
    return _connection.closed;
  }

  @override
  late Stream<UpdateNotification> updates;

  @override
  int maxReaders;

  @override
  late Future<void> isInitialized;

  @override
  DefaultSqliteOpenFactory openFactory;

  late final Mutex mutex;
  late final IsolateConnectionFactory _isolateConnectionFactory;
  late final WebSqliteConnectionImpl _connection;

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
      {this.maxReaders = AbstractSqliteDatabase.defaultMaxReaders}) {
    updates = updatesController.stream;
    mutex = Mutex();
    _isolateConnectionFactory =
        IsolateConnectionFactory(openFactory: openFactory, mutex: mutex);
    _connection = _isolateConnectionFactory.open();
    isInitialized = _init();
  }

  Future<void> _init() async {
    await _connection.isInitialized;
    _connection.updates.forEach((update) {
      updatesController.add(update);
    });
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    return _connection.readLock(callback,
        lockTimeout: lockTimeout, debugContext: debugContext);
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    return _connection.writeLock(callback,
        lockTimeout: lockTimeout, debugContext: debugContext);
  }

  @override
  Future<void> close() async {
    return _connection.close();
  }

  @override
  IsolateConnectionFactory isolateConnectionFactory() {
    return _isolateConnectionFactory;
  }
}
