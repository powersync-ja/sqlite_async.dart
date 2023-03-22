import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'sqlite_connection.dart';

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

Future<T> internalWriteTransaction<T>(SqliteWriteContext ctx,
    Future<T> Function(SqliteWriteContext tx) callback) async {
  try {
    await ctx.execute('BEGIN IMMEDIATE');
    final result = await callback(ctx);
    await ctx.execute('COMMIT');
    return result;
  } catch (e) {
    try {
      await ctx.execute('ROLLBACK');
    } catch (e) {
      // In rare cases, a ROLLBACK may fail.
      // Safe to ignore.
    }
    rethrow;
  }
}

Future<T> asyncDirectTransaction<T>(sqlite.Database db,
    FutureOr<T> Function(sqlite.Database db) callback) async {
  for (var i = 50; i >= 0; i--) {
    try {
      db.execute('BEGIN IMMEDIATE');
      late T result;
      try {
        result = await callback(db);
        db.execute('COMMIT');
      } catch (e) {
        try {
          db.execute('ROLLBACK');
        } catch (e2) {
          // Safe to ignore
        }
        rethrow;
      }

      return result;
    } catch (e) {
      if (e is sqlite.SqliteException) {
        if (e.resultCode == 5 && i != 0) {
          // SQLITE_BUSY
          await Future.delayed(const Duration(milliseconds: 50));
          continue;
        }
      }
      rethrow;
    }
  }
  throw AssertionError('Should not reach this');
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
Future<Set<String>> getSourceTables(SqliteReadContext ctx, String sql) async {
  final rows = await ctx.getAll('EXPLAIN $sql');
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

class SubscribeToUpdates {
  final SendPort port;

  SubscribeToUpdates(this.port);
}

class UnsubscribeToUpdates {
  final SendPort port;

  UnsubscribeToUpdates(this.port);
}
