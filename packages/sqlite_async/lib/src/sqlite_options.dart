/// @docImport 'dart:isolate';
/// @docImport 'package:sqlite3/common.dart';
library;

final class WebSqliteOptions {
  final String workerUri;
  final String wasmUri;

  @Deprecated('Use default WebSqliteOptions constructor instead')
  const factory WebSqliteOptions.defaults() = WebSqliteOptions;

  const WebSqliteOptions(
      {this.wasmUri = 'sqlite3.wasm', this.workerUri = 'db_worker.js'});
}

final class SqliteOptions {
  /// SQLite journal mode. Defaults to [SqliteJournalMode.wal].
  final SqliteJournalMode? journalMode;

  /// SQLite synchronous flag. Defaults to [SqliteSynchronous.normal], which
  /// is safe for WAL mode.
  final SqliteSynchronous? synchronous;

  /// Journal/WAL size limit. Defaults to 6MB.
  /// The WAL may grow large than this limit during writes, but SQLite will
  /// attempt to truncate the file afterwards.
  final int? journalSizeLimit;

  final WebSqliteOptions webSqliteOptions;

  /// Timeout waiting for locks to be released by other connections.
  /// Defaults to 30 seconds.
  /// Set to null or [Duration.zero] to fail immediately when the database is locked.
  final Duration? lockTimeout;

  /// Whether queries should be added to the `dart:developer` timeline.
  ///
  /// By default, this is enabled if the `dart.vm.product` compile-time variable
  /// is not set to `true`. For Flutter apps, this means that [profileQueries]
  /// is enabled by default in debug and profile mode.
  final bool profileQueries;

  /// The maximum amount of concurrent readers allowed on opened database pools.
  ///
  /// Depending on the target platforms, fewer readers than requested here might
  /// be supported. For instance, this package does not currently open
  /// additional readers on the web.
  final int maxReaders;

  /// The amount of prepared statements to cache.
  ///
  /// For each SQLite connection, up to [preparedStatementCacheSize] statements
  /// will be cached in an LRU cache. This allows re-using prepared statements
  /// instead of parsing and optimizing them again, which improves performance
  /// for frequently-used statements like watched queries.
  ///
  /// Be aware that active prepared statements may alter the operation of the
  /// database, for instance because they might keep some database resources
  /// locked. Statements are [CommonPreparedStatement.reset] before being stored
  /// in the cache, but enabling a statement cache is still something that
  /// should be tested carefully.
  ///
  /// This is currently disabled by default (set to `0`).
  final int preparedStatementCacheSize;

  /// Whether to use background isolates to open database connections and to run
  /// queries.
  ///
  /// This is enabled by default, and the recommended option for almost all
  /// workloads: Because SQLite queries block on synchronous IO, running them in
  /// an UI isolate degrades UI performance and can cause dropped frames.
  /// Running queries on background isolates also allows reads to run in
  /// parallel (see [maxReaders]), further improving performance for read-heavy
  /// workloads.
  ///
  /// In special setups, avoiding synchronous IO may not be necessary.
  /// Background services running on a separate Flutter engine (or short-lived
  /// tasks spawned with [Isolate.run] needing database access) already run on a
  /// background thread, and synchronous IO may be acceptable there.
  /// For these setups, disabling background isolates may be faster (as there
  /// is no [SendPort] overhead).
  ///
  /// When this is disabled, statements run synchronously on the calling
  /// isolate. This package still uses an asynchronous pool to obtain
  /// connections, preventing isolates from issuing writes in parallel (as that
  /// would cause `SQLITE_BUSY` errors).
  ///
  /// This option has no effect on the web.
  final bool useBackgroundIsolates;

  @Deprecated('Use default SqliteOptions constructor instead')
  const factory SqliteOptions.defaults() = SqliteOptions;

  const SqliteOptions({
    this.journalMode = SqliteJournalMode.wal,
    this.journalSizeLimit = 6 * 1024 * 1024,
    this.synchronous = SqliteSynchronous.normal,
    this.webSqliteOptions = const WebSqliteOptions(),
    this.lockTimeout = const Duration(seconds: 30),
    this.profileQueries = _profileQueriesByDefault,
    this.maxReaders = defaultMaxReaders,
    this.preparedStatementCacheSize = 0,
    this.useBackgroundIsolates = true,
  });

  /// Creates a new options instance by applying overrides from parameters.
  ///
  /// Only non-nullable fields can be changed this way. For other fields, create
  /// a new instance manually.
  SqliteOptions copyWith({
    WebSqliteOptions? webSqliteOptions,
    bool? profileQueries,
    int? maxReaders,
    int? preparedStatementCacheSize,
    bool? useBackgroundIsolates,
  }) {
    return SqliteOptions(
      journalMode: journalMode,
      synchronous: synchronous,
      journalSizeLimit: journalSizeLimit,
      webSqliteOptions: webSqliteOptions ?? this.webSqliteOptions,
      lockTimeout: lockTimeout,
      profileQueries: profileQueries ?? this.profileQueries,
      maxReaders: maxReaders ?? this.maxReaders,
      preparedStatementCacheSize:
          preparedStatementCacheSize ?? this.preparedStatementCacheSize,
      useBackgroundIsolates:
          useBackgroundIsolates ?? this.useBackgroundIsolates,
    );
  }

  // https://api.flutter.dev/flutter/foundation/kReleaseMode-constant.html
  static const _profileQueriesByDefault =
      !bool.fromEnvironment('dart.vm.product');

  /// The maximum number of concurrent read transactions if not explicitly
  /// specified.
  static const int defaultMaxReaders = 5;
}

/// SQLite journal mode. Set on the primary connection.
/// This library is written with WAL mode in mind - other modes may cause
/// unexpected locking behavior.
enum SqliteJournalMode {
  /// Use a write-ahead log instead of a rollback journal.
  /// This provides good performance and concurrency.
  wal('WAL'),
  delete('DELETE'),
  truncate('TRUNCATE'),
  persist('PERSIST'),
  memory('MEMORY'),
  off('OFF');

  final String name;

  const SqliteJournalMode(this.name);
}

/// SQLite file commit mode.
enum SqliteSynchronous {
  normal('NORMAL'),
  full('FULL'),
  off('OFF');

  final String name;

  const SqliteSynchronous(this.name);
}
