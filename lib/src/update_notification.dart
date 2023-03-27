import 'package:collection/collection.dart';

/// Notification of an update to one or more tables, for the purpose of realtime change
/// notifications.
class UpdateNotification {
  /// Table name
  final Set<String> tables;

  const UpdateNotification(this.tables);

  const UpdateNotification.empty() : tables = const {};
  UpdateNotification.single(String table) : tables = {table};

  @override
  bool operator ==(Object other) {
    return other is UpdateNotification &&
        const SetEquality<String>().equals(other.tables, tables);
  }

  @override
  int get hashCode {
    return Object.hashAllUnordered(tables);
  }

  @override
  String toString() {
    return "UpdateNotification<$tables>";
  }

  /// True if any of the supplied tables have been modified.
  ///
  /// Important: Use lower case for each table in [tableFilter].
  bool containsAny(Set<String> tableFilter) {
    for (var table in tables) {
      if (tableFilter.contains(table.toLowerCase())) {
        return true;
      }
    }
    return false;
  }
}
