import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_sqlite_async/src/executor.dart';
import 'package:sqlite_async/sqlite_async.dart';

/// Wraps a sqlite_async [SqliteConnection] as a Drift [DatabaseConnection].
///
/// The SqliteConnection must be instantiated before constructing this, and
/// is not closed when [SqliteAsyncDriftConnection.close] is called.
///
/// This class handles delegating Drift's queries and transactions to the
/// [SqliteConnection], and passes on any table updates from the
/// [SqliteConnection] to Drift.
class SqliteAsyncDriftConnection extends DatabaseConnection {
  late StreamSubscription _updateSubscription;

  /// [transformTableUpdates] is useful to map local table names from PowerSync that are backed by a view name
  /// which is the entity that the user interacts with.
  SqliteAsyncDriftConnection(
    SqliteConnection db, {
    bool logStatements = false,
    Set<TableUpdate> Function(UpdateNotification)? transformTableUpdates,
  }) : super(SqliteAsyncQueryExecutor(db, logStatements: logStatements)) {
    _updateSubscription = (db as SqliteQueries).updates!.listen((event) {
      final Set<TableUpdate> setUpdates;
      if (transformTableUpdates != null) {
        setUpdates = transformTableUpdates(event);
      } else {
        setUpdates = <TableUpdate>{};
        for (var tableName in event.tables) {
          setUpdates.add(TableUpdate(tableName));
        }
      }
      super.streamQueries.handleTableUpdates(setUpdates);
    });
  }

  @override
  Future<void> close() async {
    await _updateSubscription.cancel();
    await super.close();
  }
}
