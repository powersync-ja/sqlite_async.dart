class SqliteOptions {
  /// SQLite journal mode. Defaults to [SqliteJOurnalMode.wal].
  final SqliteJournalMode? journalMode;

  /// SQLite synchronous flag. Defaults to [SqliteSynchronous.NORMAL], which
  /// is safe for WAL journal mode.
  final SqliteSynchronous? synchronous;

  /// Journal/WAL size limit. Defaults to 2MB.
  /// The WAL may grow large than this limit during writes, but SQLite will
  /// attempt to truncate the file afterwards.
  final int? journalSizeLimit;

  const SqliteOptions.defaults()
      : journalMode = SqliteJournalMode.wal,
        journalSizeLimit = 6 * 1024 * 1024, // 1.5x the default checkpoint size
        synchronous = SqliteSynchronous.normal;

  const SqliteOptions(
      {this.journalMode, this.journalSizeLimit, this.synchronous});
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
