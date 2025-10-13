# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 2025-10-13

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`sqlite_async` - `v0.12.2`](#sqlite_async---v0122)
 - [`drift_sqlite_async` - `v0.2.5`](#drift_sqlite_async---v025)

---

#### `sqlite_async` - `v0.12.2`

 - Add `withAllConnections` method to run statements on all connections in the pool.

#### `drift_sqlite_async` - `v0.2.5`

 - Allow customizing update notifications from `sqlite_async`.


## 2025-08-08

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`sqlite_async` - `v0.12.1`](#sqlite_async---v0121)
 - [`sqlite_async` - `v0.12.0`](#sqlite_async---v0120)
 - [`drift_sqlite_async` - `v0.2.3+1`](#drift_sqlite_async---v0231)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `drift_sqlite_async` - `v0.2.3+1`

---

#### `sqlite_async` - `v0.12.1`

- Fix distributing updates from shared worker.

#### `sqlite_async` - `v0.12.0`

 - Avoid large transactions creating a large internal update queue.


## 2025-07-29

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`sqlite_async` - `v0.11.8`](#sqlite_async---v0118)
 - [`drift_sqlite_async` - `v0.2.3`](#drift_sqlite_async---v023)

---

#### `sqlite_async` - `v0.11.8`

- Support nested transactions (emulated with `SAVEPOINT` statements).
- Fix web compilation issues with version `2.8.0` of `package:sqlite3`.

#### `drift_sqlite_async` - `v0.2.3`

- Support nested transactions.

## 2025-06-03

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`sqlite_async` - `v0.11.7`](#sqlite_async---v0117)

---

#### `sqlite_async` - `v0.11.7`

- Shared worker: Release locks owned by connected client tab when it closes.
- Fix web concurrency issues: Consistently apply a shared mutex or let a shared
  worker coordinate access.

## 2025-05-28

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`sqlite_async` - `v0.11.6`](#sqlite_async---v0116)

---

#### `sqlite_async` - `v0.11.6`

- Native: Consistently report errors when opening the database instead of
  causing unhandled exceptions.

## 2025-05-22

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`sqlite_async` - `v0.11.5`](#sqlite_async---v0115)

---

#### `sqlite_async` - `v0.11.5`

- Allow profiling queries. Queries are profiled by default in debug and profile builds, the runtime
  for queries is added to profiling timelines under the `sqlite_async` tag.
- Fix cancelling `watch()` queries sometimes taking longer than necessary.
- Fix web databases not respecting lock timeouts.

## 2024-11-06

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`drift_sqlite_async` - `v0.2.0`](#drift_sqlite_async---v020)

---

#### `drift_sqlite_async` - `v0.2.0`

 - Automatically run Drift migrations


## 2024-11-06

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`sqlite_async` - `v0.11.0`](#sqlite_async---v0110)
 - [`drift_sqlite_async` - `v0.2.0-alpha.4`](#drift_sqlite_async---v020-alpha4)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `drift_sqlite_async` - `v0.2.0-alpha.4`

---

#### `sqlite_async` - `v0.11.0`

 - Automatically flush IndexedDB storage to fix durability issues


## 2024-11-01

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`sqlite_async` - `v0.10.1`](#sqlite_async---v0101)
 - [`drift_sqlite_async` - `v0.2.0-alpha.3`](#drift_sqlite_async---v020-alpha3)

---

#### `sqlite_async` - `v0.10.1`

 - For database setups not using a shared worker, use a `BroadcastChannel` to share updates across different tabs.

#### `drift_sqlite_async` - `v0.2.0-alpha.3`

 - Bump `sqlite_async` to v0.10.1


## 2024-10-28

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`drift_sqlite_async` - `v0.2.0-alpha.2`](#drift_sqlite_async---v020-alpha2)
 - [`sqlite_async` - `v0.10.0`](#sqlite_async---v0100)

---

#### `drift_sqlite_async` - `v0.2.0-alpha.2`

 - Bump sqlite_async to v0.10.0

#### `sqlite_async` - `v0.10.0`

 - Add the `exposeEndpoint()` method available on web databases. It returns a serializable
  description of the database endpoint that can be sent across workers.
  This allows sharing an opened database connection across workers.


## 2024-09-03

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`sqlite_async` - `v0.9.0`](#sqlite_async---v090)
 - [`drift_sqlite_async` - `v0.1.0-alpha.7`](#drift_sqlite_async---v010-alpha7)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `drift_sqlite_async` - `v0.1.0-alpha.7`

---

#### `sqlite_async` - `v0.9.0`

 - Support the latest version of package:web and package:sqlite3_web

 - Export sqlite3 `open` for packages that depend on `sqlite_async`


## 2024-08-21

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`sqlite_async` - `v0.8.3`](#sqlite_async---v083)
 - [`drift_sqlite_async` - `v0.1.0-alpha.6`](#drift_sqlite_async---v010-alpha6)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `drift_sqlite_async` - `v0.1.0-alpha.6`

---

#### `sqlite_async` - `v0.8.3`

 - Updated web database implementation for get and getOptional. Fixed refreshSchema not working in web.


## 2024-08-20

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`sqlite_async` - `v0.8.2`](#sqlite_async---v082)
 - [`drift_sqlite_async` - `v0.1.0-alpha.5`](#drift_sqlite_async---v010-alpha5)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

 - `drift_sqlite_async` - `v0.1.0-alpha.5`

---

#### `sqlite_async` - `v0.8.2`

 - **FEAT**: Added `refreshSchema()`, allowing queries and watch calls to work against updated schemas.


## 2024-07-10

### Changes

---

Packages with breaking changes:

- There are no breaking changes in this release.

Packages with other changes:

- [`sqlite_async` - `v0.8.1`](#sqlite_async---v081)
- [`drift_sqlite_async` - `v0.1.0-alpha.4`](#drift_sqlite_async---v010-alpha4)

Packages with dependency updates only:

> Packages listed below depend on other packages in this workspace that have had changes. Their versions have been incremented to bump the minimum dependency versions of the packages they depend upon in this project.

#### `drift_sqlite_async` - `v0.1.0-alpha.4`

- **FEAT**: web support.

---

#### `sqlite_async` - `v0.8.1`

- **FEAT**: use navigator locks.
