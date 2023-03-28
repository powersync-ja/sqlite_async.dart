/// Given a list of columns, return an expression extracting the columns from a
/// list of JSON-encoded objects.
///
/// This call:
///
/// ```dart
/// selectJsonColumns(['name', 'email'])('?')
/// ```
///
/// Produces the equivalent of:
/// ```dart
/// "SELECT json_each.value ->> 'name' as name, json_each.value ->> 'email' as email FROM json_each(?)"
/// ```
PlaceholderQueryFragment selectJsonColumns(List<String> columns) {
  String extract = columns.map((e) {
    return "json_extract(json_each.value, ${quoteJsonPath(e)}) as ${quoteIdentifier(e)}";
  }).join(', ');

  return PlaceholderQueryFragment._("SELECT $extract FROM json_each(", ")");
}

/// Similar to [selectJsonColumns], but allows specifying different output columns.
/// This is useful for using on a List of Lists, instead of a List of Objects.
///
/// Example:
/// ```dart
/// selectJsonColumnMap({0: 'name', 1: 'email'})('?')
/// ```
PlaceholderQueryFragment selectJsonColumnMap(Map<Object, String>? columnMap) {
  String extract;
  if (columnMap != null) {
    extract = columnMap.entries.map((e) {
      final key = e.key;
      if (key is int) {
        return "json_extract(json_each.value, ${quoteJsonIndex(key)}) as ${quoteIdentifier(e.value)}";
      } else if (key is String) {
        return "json_extract(json_each.value, ${quoteJsonPath(key)})  as ${quoteIdentifier(e.value)}";
      } else {
        throw ArgumentError('Key must be an int or String');
      }
    }).join(', ');
  } else {
    extract = "json_each.value as value";
  }

  return PlaceholderQueryFragment._("SELECT $extract FROM json_each(", ")");
}

String quoteIdentifier(String s) {
  return '"${s.replaceAll('"', '""')}"';
}

String quoteString(String s) {
  return "'${s.replaceAll("'", "''")}'";
}

String quoteJsonPath(String path) {
  return quoteString('\$.$path');
}

String quoteJsonIndex(int index) {
  return quoteString('\$[$index]');
}

/// A query fragment that can be embedded in another query.
///
/// When embedded in a query directly or with [toString], the default
/// placeholder "?" is used.
///
/// Can be called as a function with a different placeholder if desired.
class PlaceholderQueryFragment {
  final String _before;
  final String _after;

  const PlaceholderQueryFragment._(this._before, this._after);

  /// Return a query fragment with the specified placeholder value.
  String call([String placeholder = '?']) {
    return '$_before$placeholder$_after';
  }

  /// Return a query fragment with the default placeholder value of '?'.
  @override
  String toString() {
    return call();
  }
}
