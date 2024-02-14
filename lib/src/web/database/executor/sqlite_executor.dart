// Abstract class which provides base methods required for Context providers
import 'dart:async';

import 'package:sqlite_async/sqlite3_common.dart';

/// Abstract class for providing basic SQLite operations
/// Specific DB implementations such as Drift can be adapted to
/// this interface
abstract class SQLExecutor {
  bool get closed;

  Stream<Set<String>> updateStream = Stream.empty();

  Future<void> close();

  FutureOr<ResultSet> select(String sql, [List<Object?> parameters = const []]);

  FutureOr<void> executeBatch(String sql, List<List<Object?>> parameterSets) {}
}
