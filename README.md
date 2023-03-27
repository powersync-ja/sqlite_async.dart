# sqlite_async 

High-performance asynchronous interface for SQLite on Dart & Flutter.

[SQLite](https://www.sqlite.org/) is small, fast, has a lot of built-in functionality, and works
great as an in-app database. However, SQLite is designed for many different use cases, and requires
some configuration for optimal performance as an in-app database.

The [sqlite3](https://pub.dev/packages/sqlite3) Dart bindings are great for direct synchronous access
to a SQLite database, but leaves the configuration the developer.

This library wraps the bindings and configures the database with a good set of defaults, with
all database calls being asynchronous to avoid blocking the UI, while still providing direct SQL
query access.

## Features

 * All operations are asynchronous by default - does not block the main isolate.
 * Concurrent transactions supported by default - one write transaction and many multiple read transactions.
 * Uses WAL mode with minimal locking.
 * Direct synchronous access in an isolate is supported for performance-sensitive use cases. 
