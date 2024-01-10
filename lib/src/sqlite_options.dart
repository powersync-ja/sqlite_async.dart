import 'package:sqlite3/wasm.dart';

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

  /// The implementation for SQLite
  /// This is required for Web WASM
  ///   final wasmSqlite3 =
  ///       await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.debug.wasm'));
  ///   wasmSqlite3.registerVirtualFileSystem(
  ///       await IndexedDbFileSystem.open(dbName: 'sqlite3-example'),
  ///       makeDefault: true,
  ///    );
  ///  Pass the initialized wasmSqlite3 here
  final WasmSqlite3? wasmSqlite3;

  const SqliteOptions.defaults()
      : journalMode = SqliteJournalMode.wal,
        journalSizeLimit = 6 * 1024 * 1024, // 1.5x the default checkpoint size
        synchronous = SqliteSynchronous.normal,
        wasmSqlite3 = null;

  const SqliteOptions(
      {this.journalMode = SqliteJournalMode.wal,
      this.journalSizeLimit = 6 * 1024 * 1024,
      this.synchronous = SqliteSynchronous.normal,
      this.wasmSqlite3 = null});
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
