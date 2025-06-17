import 'dart:async';
import 'dart:convert';

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
