import 'package:drift/drift.dart';
import 'package:drift_sqlite_async/drift_sqlite_async.dart';
import 'package:sqlite_async/sqlite_async.dart';

part 'with_migrations.g.dart';

class TodoItems extends Table {
  @override
  String get tableName => 'todos';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get description => text()();
}

@DriftDatabase(tables: [TodoItems])
class AppDatabase extends _$AppDatabase {
  AppDatabase(SqliteConnection db) : super(SqliteAsyncDriftConnection(db));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        // In this example, the schema is managed by Drift
        await m.createAll();
      },
    );
  }
}

Future<void> main() async {
  final db = SqliteDatabase(path: 'with_migrations.db');

  await db.execute(
      'CREATE TABLE IF NOT EXISTS todos(id integer primary key, description text)');

  final appdb = AppDatabase(db);

  // Watch a query on the Drift database
  appdb.select(appdb.todoItems).watch().listen((todos) {
    print('Todos: $todos');
  });

  // Insert using the Drift database
  await appdb
      .into(appdb.todoItems)
      .insert(TodoItemsCompanion.insert(description: 'Test Drift'));

  // Insert using the sqlite_async database
  await db.execute('INSERT INTO todos(description) VALUES(?)', ['Test Direct']);

  await Future.delayed(const Duration(milliseconds: 100));

  await appdb.close();
  await db.close();
}
