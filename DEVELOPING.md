# Developing Instructions

## Workers and WebAssembly modules

Running `sqlite_async` on the web requires a `sqlite3.wasm` file that can be downloaded with `tool/sqlite3_wasm_download.dart`.
Additionally, we need a web worker that can be compiled with

```
dart compile js -o assets/db_worker.js packages/sqlite_async/lib/src/web/worker/worker.dart
```

On release builds, we compile with `-O4`. For tests, we compile with `-O4 --no-minify`. For debugging, compiling
with `-O0` might be better.

## Changelogs

When making new changes, bump the package version and add a `-wip` suffix. For example:

1. The current version is `1.0.0` and your PR adds a breaking change: The new version should be `2.0.0-wip`.
2. The current version is `1.0.0` and your PR adds a new feature: The new version should be `1.1.0-wip`.

Update both the changelog and `pubspec.yaml`. For breaking changes, you might also have to update the
version of dependent packages.

## Releases

The release process consists of two parts, publishing new versions to pub.dev and uploading workers as
assets to a GitHub release.

Most of this process is automated, the workflow looks like this:

1. Remove the `-wip` suffix from the package version and ensure everything looks good.
2. Wait for that change to land on `main`.
3. Depending on the updated package, tag:
    - `sqlite_async-v$major.$minor$.$patch`.
    - `drift_sqlite_async-v$major.$minor$.$patch`.
4. Push those tags, which will trigger a pub.dev release.
5. When updating `sqlite_async`, pushing the tag will create a draft release. Copy the changelog and mark that release as public.
