# drift_sqlite_async

`drift_sqlite_async` allows using drift on an sqlite_async database - the APIs from both can be seamlessly used together in the same application.

Supported functionality:

1. All queries including select, insert, update, delete.
2. Transactions and nested transactions.
3. Table updates are propagated between sqlite_async and Drift - watching queries works using either API.
4. Select queries can run concurrently with writes and other select statements.
5. Drift migrations are supported (optional).

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

## Web

Note: Web support is currently in Beta.

Web support requires Sqlite3 WASM and web worker Javascript files to be accessible. These file need to be put into the `web/` directory of your app.

The compiled web worker files can be found in our Github [releases](https://github.com/powersync-ja/sqlite_async.dart/releases)
The `sqlite3.wasm` asset can be found [here](https://github.com/simolus3/sqlite3.dart/releases)

In the end your `web/` directory will look like the following

```
web/
├── favicon.png
├── index.html
├── manifest.json
├── db_worker.js
└── sqlite3.wasm
```
