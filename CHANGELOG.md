## 0.7.0-alpha.2

- Add latest changes from master

## 0.7.0-alpha.2

- Fix re-using a shared Mutex from <https://github.com/powersync-ja/sqlite_async.dart/pull/31>

## 0.7.0-alpha.1

- Added initial support for web platform.

## 0.6.1

- Fix errors when closing a `SqliteDatabase`.
- Configure SQLite `busy_timeout` (30s default). This fixes "database is locked (code 5)" error when using multiple `SqliteDatabase` instances for the same database.
- Fix errors when opening multiple connections at the same time, e.g. when running multiple read queries concurrently
  right after opening the dtaabase.
- Improved error handling when an Isolate crashes with an uncaught error.
- Rewrite connection pool logic to fix performance issues when multiple read connections are open.
- Fix using `SqliteDatabase.isolateConnectionFactory()` in multiple isolates.

## 0.6.0

- Allow catching errors and continuing the transaction. This is technically a breaking change, although it should not be an issue in most cases.
- Add `tx.closed` and `db/tx.getAutoCommit()` to check whether transactions are active.
- Requires sqlite3 ^2.3.0 and Dart ^3.2.0.

## 0.5.2

- Fix releasing of locks when closing `SharedMutex``.

## 0.5.1

- Fix `watch` when called with query parameters.
- Clean up `-wal` and `-shm` files on close.

## 0.5.0

- No code changes.
- Updated dependencies to support sqlite3 2.x.

## 0.4.0

- Ensure database connections are cleaned up on unhandled Isolate errors.
- Minor performance improvements.

## 0.3.0

- Better error messages for recursive transactions.
- Breaking change: Error by default when starting a read transaction within a write transaction.

## 0.2.1

- Fix update notifications missing the first update.

## 0.2.0

- Initial version.
