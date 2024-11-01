## 0.10.1

- For database setups not using a shared worker, use a `BroadcastChannel` to share updates across different tabs.

## 0.10.0

- Add the `exposeEndpoint()` method available on web databases. It returns a serializable
  description of the database endpoint that can be sent across workers.
  This allows sharing an opened database connection across workers.

## 0.9.1

- Support version ^0.2.0 of package:sqlite3_web
- Fix update notifications to only fire outside transactions
- Fix update notifications to be debounced on web

## 0.9.0

- Support the latest version of package:web and package:sqlite3_web

- Export sqlite3 `open` for packages that depend on `sqlite_async`

## 0.8.3

- Updated web database implementation for get and getOptional. Fixed refreshSchema not working in web.

## 0.8.2

- **FEAT**: Added `refreshSchema()`, allowing queries and watch calls to work against updated schemas.

## 0.8.1

- Added Navigator locks for web `Mutex`s.

## 0.8.0

- Added web support (web functionality is in beta)

## 0.7.0

- BREAKING CHANGE: Update all Database types to use a `CommonDatabase` interface.
- Update `openDB` and `open` methods to be synchronous.
- Fix `ArgumentError (Invalid argument(s): argument value for 'return_value' is null)` in sqlite3 when closing the database connection by upgrading to version 2.4.4.

## 0.7.0-alpha.5

- The dependency for the `Drift` package is now removed in favour of using the new `sqlite3_web` package.
- A new implementation for WebDatabase is used for SQL database connections on web.
- New exports are added for downstream consumers of this package to extended custom workers with custom SQLite function capabilities.
- Update minimum Dart SDK to 3.4.0

## 0.7.0-alpha.4

- Add latest changes from master

## 0.7.0-alpha.3

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
