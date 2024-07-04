# drift_sqlite_async

`drift_sqlite_async` allows using drift on an sqlite_async database - the APIs from both can be seamlessly used together in the same application.

Supported functionality:
1. All queries including select, insert, update, delete.
2. Transactions and nested transactions.
3. Table updates are propagated between sqlite_async and Drift - watching queries works using either API.
4. Select queries can run concurrently with writes and other select statements.


## Usage

Use `SqliteAsyncDriftConnection` to create a DatabaseConnection / QueryExecutor for Drift from the sqlite_async SqliteDatabase:

```dart
@DriftDatabase(tables: [TodoItems])
class AppDatabase extends _$AppDatabase {
  AppDatabase(SqliteConnection db) : super(SqliteAsyncDriftConnection(db));

  @override
  int get schemaVersion => 1;
}

Future<void> main() async {
  // The sqlite_async db
  final db = SqliteDatabase(path: 'example.db');
  // The Drift db
  final appdb = AppDatabase(db);
}
```

A full example is in the `examples/` folder.

For details on table definitions and using the database, see the [Drift documentation](https://drift.simonbinder.eu/).

## Transactions and concurrency

sqlite_async uses WAL mode and multiple read connections by default, and this
is also exposed when using the database with Drift.

Drift's transactions use sqlite_async's `writeTransaction`. The same locks are used
for both, preventing conflicts.

Read-only transactions are not currently supported in Drift.

Drift's nested transactions are supported, implemented using SAVEPOINT.

Select statements in Drift use read operations (`getAll()`) in sqlite_async,
and can run concurrently with writes.

## Update notifications

sqlite_async uses SQLite's update_hook to detect changes for watching queries,
and will automatically pick up changes made using Drift. This also includes any updates from custom queries in Drift.

Changes from sqlite_async are automatically propagated to Drift when using SqliteAsyncDriftConnection.
These events are only sent while no write transaction is active.

Within Drift's transactions, Drift's own update notifications will still apply for watching queries within that transaction.

Note: There is a possibility of events being duplicated. This should not have a significant impact on most applications.