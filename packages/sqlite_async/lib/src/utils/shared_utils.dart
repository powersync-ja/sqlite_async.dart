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
  /// Wraps [updatesSync] to:
  ///
  ///   - Not fire in transactions.
  ///   - Fire asynchronously.
  ///   - Only report table names, which are buffered to avoid duplicates.
  Stream<Set<String>> get throttledUpdatedTables {
    StreamController<Set<String>>? controller;
    var pendingUpdates = <String>{};
    var paused = false;

    Timer? updateDebouncer;

    void maybeFireUpdates() {
      updateDebouncer?.cancel();
      updateDebouncer = null;

      if (paused) {
        // Continue collecting updates, but don't fire any
        return;
      }

      if (!autocommit) {
        // Inside a transaction - do not fire updates
        return;
      }

      if (pendingUpdates.isNotEmpty) {
        controller!.add(pendingUpdates);
        pendingUpdates = {};
      }
    }

    void collectUpdate(SqliteUpdate event) {
      pendingUpdates.add(event.tableName);

      updateDebouncer ??=
          Timer(const Duration(milliseconds: 1), maybeFireUpdates);
    }

    StreamSubscription? txSubscription;
    StreamSubscription? sourceSubscription;

    controller = StreamController(onListen: () {
      txSubscription = commits.listen((_) {
        maybeFireUpdates();
      }, onError: (error) {
        controller?.addError(error);
      });

      sourceSubscription = updatesSync.listen(collectUpdate, onError: (error) {
        controller?.addError(error);
      });
    }, onPause: () {
      paused = true;
    }, onResume: () {
      paused = false;
      maybeFireUpdates();
    }, onCancel: () {
      txSubscription?.cancel();
      sourceSubscription?.cancel();
    });

    return controller.stream;
  }
}
