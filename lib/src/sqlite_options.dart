class WebSqliteOptions {
  final String workerUri;
  final String wasmUri;

  const WebSqliteOptions.defaults()
      : workerUri = 'db_worker.js',
        wasmUri = 'sqlite3.wasm';

  const WebSqliteOptions(
      {this.wasmUri = 'sqlite3.wasm', this.workerUri = 'db_worker.js'});
}

class SqliteOptions {
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

  const SqliteOptions.defaults()
      : journalMode = SqliteJournalMode.wal,
        journalSizeLimit = 6 * 1024 * 1024, // 1.5x the default checkpoint size
        synchronous = SqliteSynchronous.normal,
        webSqliteOptions = const WebSqliteOptions.defaults(),
        lockTimeout = const Duration(seconds: 30);

  const SqliteOptions(
      {this.journalMode = SqliteJournalMode.wal,
      this.journalSizeLimit = 6 * 1024 * 1024,
      this.synchronous = SqliteSynchronous.normal,
      this.webSqliteOptions = const WebSqliteOptions.defaults(),
      this.lockTimeout = const Duration(seconds: 30)});
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
