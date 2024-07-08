import 'package:drift/drift.dart';
import 'package:drift_sqlite_async/drift_sqlite_async.dart';
import 'package:sqlite_async/sqlite_async.dart';

part 'database.g.dart';

class TodoItems extends Table {
  @override
  String get tableName => 'todos';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get description => text()();
}

@DriftDatabase(tables: [TodoItems])
class TodoDatabase extends _$TodoDatabase {
  TodoDatabase(SqliteConnection db) : super(SqliteAsyncDriftConnection(db));

  @override
  int get schemaVersion => 1;
}
