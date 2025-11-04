## 0.2.6

- Support latest `sqlite_async`.

## 0.2.5

 - Allow customizing update notifications from `sqlite_async`.

## 0.2.4

- Allow transforming table updates from sqlite_async.

## 0.2.3+1

 - Update a dependency to the latest release.

## 0.2.3

- Support nested transactions.

## 0.2.2

- Fix write detection when using UPDATE/INSERT/DELETE with RETURNING in raw queries.

## 0.2.1

- Fix lints.

## 0.2.0

 - Automatically run Drift migrations

## 0.2.0-alpha.4

 - Update a dependency to the latest release.

## 0.2.0-alpha.3

 - Bump `sqlite_async` to v0.10.1

## 0.2.0-alpha.2

 - Bump `sqlite_async` to v0.10.0

## 0.2.0-alpha.1

 - Support `drift` version >=2.19 and `web` v1.0.0.
 - **BREAKING CHANGE**: Nested transactions through drift no longer create SAVEPOINTs. When nesting a drift `transaction`, the transaction is reused ([#65](https://github.com/powersync-ja/sqlite_async.dart/pull/65)).

## 0.1.0-alpha.7

 - Update a dependency to the latest release.

## 0.1.0-alpha.6

 - Update a dependency to the latest release.

## 0.1.0-alpha.5

 - Update a dependency to the latest release.

## 0.1.0-alpha.4

- Import `sqlite3_common` instead of `sqlite3` for web support.

## 0.1.0-alpha.3

- Update a dependency to the latest release.

## 0.1.0-alpha.2

- Update dependency `sqlite_async` to version 0.8.0.

## 0.1.0-alpha.1

Initial release.
