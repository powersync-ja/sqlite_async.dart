# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

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
