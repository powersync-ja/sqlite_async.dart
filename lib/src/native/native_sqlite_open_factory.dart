import 'package:sqlite_async/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite3_common.dart';

import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/native/database/native_sqlite_connection_impl.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_options.dart';

/// Native implementation of [AbstractDefaultSqliteOpenFactory]
class DefaultSqliteOpenFactory extends AbstractDefaultSqliteOpenFactory {
  const DefaultSqliteOpenFactory(
      {required super.path,
      super.sqliteOptions = const SqliteOptions.defaults()});

  @override
  CommonDatabase openDB(SqliteOpenOptions options) {
    final mode = options.openMode;
    var db = sqlite.sqlite3.open(path, mode: mode, mutex: false);
    return db;
  }

  @override
  List<String> pragmaStatements(SqliteOpenOptions options) {
    List<String> statements = [];

    if (sqliteOptions.lockTimeout != null) {
      // May be replaced by a Dart-level retry mechanism in the future
      statements.add(
          'PRAGMA busy_timeout = ${sqliteOptions.lockTimeout!.inMilliseconds}');
    }

    if (options.primaryConnection && sqliteOptions.journalMode != null) {
      // Persisted - only needed on the primary connection
      statements
          .add('PRAGMA journal_mode = ${sqliteOptions.journalMode!.name}');
    }
    if (!options.readOnly && sqliteOptions.journalSizeLimit != null) {
      // Needed on every writable connection
      statements.add(
          'PRAGMA journal_size_limit = ${sqliteOptions.journalSizeLimit!}');
    }
    if (sqliteOptions.synchronous != null) {
      // Needed on every connection
      statements.add('PRAGMA synchronous = ${sqliteOptions.synchronous!.name}');
    }
    return statements;
  }

  @override
  SqliteConnection openConnection(SqliteOpenOptions options) {
    return SqliteConnectionImpl(
      primary: options.primaryConnection,
      readOnly: options.readOnly,
      mutex: options.mutex!,
      debugName: options.debugName,
      updates: options.updates,
      openFactory: this,
    );
  }
}
