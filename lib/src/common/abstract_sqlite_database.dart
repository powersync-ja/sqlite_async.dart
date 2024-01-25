import 'dart:async';

import 'package:sqlite_async/src/common/abstract_isolate_connection_factory.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';

/// A SQLite database instance.
///
/// Use one instance per database file. If multiple instances are used, update
/// notifications may not trigger, and calls may fail with "SQLITE_BUSY" errors.
abstract class AbstractSqliteDatabase extends SqliteConnection
    with SqliteQueries {
  /// The maximum number of concurrent read transactions if not explicitly specified.
  static const int defaultMaxReaders = 5;

  /// Maximum number of concurrent read transactions.
  int get maxReaders;

  /// Factory that opens a raw database connection in each isolate.
  ///
  /// This must be safe to pass to different isolates.
  ///
  /// Use a custom class for this to customize the open process.
  AbstractDefaultSqliteOpenFactory get openFactory;

  /// Use this stream to subscribe to notifications of updates to tables.
  Stream<UpdateNotification> get updates;

  final StreamController<UpdateNotification> updatesController =
      StreamController.broadcast();

  Future<void> get isInitialized;

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
}
