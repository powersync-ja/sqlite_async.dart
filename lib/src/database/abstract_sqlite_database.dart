import 'dart:async';

import 'package:sqlite_async/src/isolate_connection_factory/abstract_isolate_connection_factory.dart';

import '../../definitions.dart';

/// A SQLite database instance.
///
/// Use one instance per database file. If multiple instances are used, update
/// notifications may not trigger, and calls may fail with "SQLITE_BUSY" errors.
abstract class AbstractSqliteDatabase
    with SqliteQueries
    implements SqliteConnection {
  /// The maximum number of concurrent read transactions if not explicitly specified.
  static const int defaultMaxReaders = 5;

  /// Maximum number of concurrent read transactions.
  late final int maxReaders;

  /// Factory that opens a raw database connection in each isolate.
  ///
  /// This must be safe to pass to different isolates.
  ///
  /// Use a custom class for this to customize the open process.
  late final SqliteOpenFactory openFactory;

  /// Use this stream to subscribe to notifications of updates to tables.
  @override
  late final Stream<UpdateNotification> updates;

  final StreamController<UpdateNotification> updatesController =
      StreamController.broadcast();

  late final Future<void> isInitialized;

  /// Wait for initialization to complete.
  ///
  /// While initializing is automatic, this helps to catch and report initialization errors.
  Future<void> initialize() async {
    await isInitialized;
  }

  /// A connection factory that can be passed to different isolates.
  ///
  /// Use this to access the database in background isolates.
  AbstractIsolateConnectionFactory isolateConnectionFactory();

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
      {Duration? lockTimeout});

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
      {Duration? lockTimeout});

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext});

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext});
}
