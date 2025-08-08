import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../sqlite_connection.dart';

Future<T> internalReadTransaction<T>(SqliteReadContext ctx,
    Future<T> Function(SqliteReadContext tx) callback) async {
  try {
    await ctx.getAll('BEGIN');
    final result = await callback(ctx);
    await ctx.getAll('END TRANSACTION');
    return result;
  } catch (e) {
    try {
      await ctx.getAll('ROLLBACK');
    } catch (e) {
      // In rare cases, a ROLLBACK may fail.
      // Safe to ignore.
    }
    rethrow;
  }
}

/// Given a SELECT query, return the tables that the query depends on.
Future<Set<String>> getSourceTablesText(
    SqliteReadContext ctx, String sql) async {
  final rows = await ctx.getAll('EXPLAIN QUERY PLAN $sql');
  Set<String> tables = {};
  final re = RegExp(r'^(SCAN|SEARCH)( TABLE)? (.+?)( USING .+)?$');
  for (var row in rows) {
    final detail = row['detail'];
    final match = re.firstMatch(detail);
    if (match != null) {
      tables.add(match.group(3)!);
    }
  }
  return tables;
}

/// Given a SELECT query, return the tables that the query depends on.
Future<Set<String>> getSourceTables(SqliteReadContext ctx, String sql,
    [List<Object?> parameters = const []]) async {
  final rows = await ctx.getAll('EXPLAIN $sql', parameters);
  List<int> rootpages = [];
  for (var row in rows) {
    if (row['opcode'] == 'OpenRead' && row['p3'] == 0 && row['p2'] is int) {
      rootpages.add(row['p2']);
    }
  }
  var tableRows = await ctx.getAll(
      'SELECT tbl_name FROM sqlite_master WHERE rootpage IN (SELECT json_each.value FROM json_each(?))',
      [jsonEncode(rootpages)]);

  Set<String> tables = {for (var row in tableRows) row['tbl_name']};
  return tables;
}

class InitDb {
  const InitDb();
}

Object? mapParameter(Object? parameter) {
  if (parameter == null ||
      parameter is int ||
      parameter is String ||
      parameter is bool ||
      parameter is num ||
      parameter is List<int>) {
    return parameter;
  } else {
    return jsonEncode(parameter);
  }
}

List<Object?> mapParameters(List<Object?> parameters) {
  return [for (var p in parameters) mapParameter(p)];
}

extension ThrottledUpdates on CommonDatabase {
  /// An unthrottled stream of updated tables that emits on every commit.
  ///
  /// A paused subscription on this stream will buffer changed tables into a
  /// growing set instead of losing events, so this stream is simple to throttle
  /// downstream.
  Stream<Set<String>> get updatedTables {
    final listeners = <_UpdateListener>[];
    var uncommitedUpdates = <String>{};
    var underlyingSubscriptions = <StreamSubscription<void>>[];

    void handleUpdate(SqliteUpdate update) {
      uncommitedUpdates.add(update.tableName);
    }

    void afterCommit() {
      for (final listener in listeners) {
        listener.notify(uncommitedUpdates);
      }

      uncommitedUpdates.clear();
    }

    void afterRollback() {
      uncommitedUpdates.clear();
    }

    void addListener(_UpdateListener listener) {
      listeners.add(listener);

      if (listeners.length == 1) {
        // First listener, start listening for raw updates on underlying
        // database.
        underlyingSubscriptions = [
          updatesSync.listen(handleUpdate),
          commits.listen((_) => afterCommit()),
          commits.listen((_) => afterRollback())
        ];
      }
    }

    void removeListener(_UpdateListener listener) {
      listeners.remove(listener);
      if (listeners.isEmpty) {
        for (final sub in underlyingSubscriptions) {
          sub.cancel();
        }
      }
    }

    return Stream.multi(
      (listener) {
        final wrapped = _UpdateListener(listener);
        addListener(wrapped);

        listener.onResume = wrapped.addPending;
        listener.onCancel = () => removeListener(wrapped);
      },
      isBroadcast: true,
    );
  }
}

class _UpdateListener {
  final MultiStreamController<Set<String>> downstream;
  Set<String> buffered = {};

  _UpdateListener(this.downstream);

  void notify(Set<String> pendingUpdates) {
    buffered.addAll(pendingUpdates);
    if (!downstream.isPaused) {
      addPending();
    }
  }

  void addPending() {
    if (buffered.isNotEmpty) {
      downstream.add(buffered);
      buffered = {};
    }
  }
}
