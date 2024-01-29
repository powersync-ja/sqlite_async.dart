# sqlite_async 

High-performance asynchronous interface for SQLite on Dart & Flutter.

[SQLite](https://www.sqlite.org/) is small, fast, has a lot of built-in functionality, and works
great as an in-app database. However, SQLite is designed for many different use cases, and requires
some configuration for optimal performance as an in-app database.

The [sqlite3](https://pub.dev/packages/sqlite3) Dart bindings are great for direct synchronous access
to a SQLite database, but leaves the configuration up to the developer.

This library wraps the bindings and configures the database with a good set of defaults, with
all database calls being asynchronous to avoid blocking the UI, while still providing direct SQL
query access.

## Features

 * All operations are asynchronous by default - does not block the main isolate.
 * Watch a query to automatically re-run on changes to the underlying data.
 * Concurrent transactions supported by default - one write transaction and many multiple read transactions.
 * Uses WAL mode for fast writes and running read transactions concurrently with a write transaction.
 * Direct synchronous access in an isolate is supported for performance-sensitive use cases. 
 * Automatically convert query args to JSON where applicable, making JSON1 operations simple.
 * Direct SQL queries - no wrapper classes or code generation required.

See this [blog post](https://www.powersync.co/blog/sqlite-optimizations-for-ultra-high-performance),
explaining why these features are important for using SQLite.

## Installation

```sh
dart pub add sqlite_async
```

For flutter applications, additionally add `sqlite3_flutter_libs` to include the native SQLite
library.

For other platforms, see the [sqlite3 package docs](https://pub.dev/packages/sqlite3#supported-platforms).

Web is currently not supported.

## Getting Started

```dart
import 'package:sqlite_async/sqlite_async.dart';

final migrations = SqliteMigrations()
  ..add(SqliteMigration(1, (tx) async {
    await tx.execute(
        'CREATE TABLE test_data(id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT)');
  }));

void main() async {
  final db = SqliteDatabase(path: 'test.db');
  await migrations.migrate(db);

  // Use execute() or executeBatch() for INSERT/UPDATE/DELETE statements
  await db.executeBatch('INSERT INTO test_data(data) values(?)', [
    ['Test1'],
    ['Test2']
  ]);

  // Use getAll(), get() or getOptional() for SELECT statements
  var results = await db.getAll('SELECT * FROM test_data');
  print('Results: $results');

  // Combine multiple statements into a single write transaction for:
  // 1. Atomic persistence (all updates are either applied or rolled back).
  // 2. Improved throughput.
  await db.writeTransaction((tx) async {
    await tx.execute('INSERT INTO test_data(data) values(?)', ['Test3']);
    await tx.execute('INSERT INTO test_data(data) values(?)', ['Test4']);
  });

  await db.close();
}
```

# Web

Web support is provided by the [Drift](https://drift.simonbinder.eu/web/) library.

Web support requires Sqlite3 WASM and Drift worker Javascript files to be accessible via configurable URIs.

Default URIs are shown in the example below. URIs only need to be specified if they differ from default values.

Watched queries and table change notifications are only supported when using a custom Drift worker. [TBD release link]

Setup

``` Dart 
import 'package:sqlite_async/sqlite_async.dart';

final db = SqliteDatabase(
    path: 'test',
    options: SqliteOptions(
        webSqliteOptions: WebSqliteOptions(
            wasmUri: 'sqlite3.wasm', workerUri: 'drift_worker.js')));

```

