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
