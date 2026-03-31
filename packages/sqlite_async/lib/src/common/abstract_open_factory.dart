/// @docImport '../native/native_sqlite_open_factory.dart';
/// @docImport '../web/web_sqlite_open_factory.dart';
library;

import 'package:meta/meta.dart';
import 'package:sqlite3/common.dart' as sqlite;

import '../impl/platform.dart' as platform;

import '../sqlite_options.dart';

/// Factory to create new SQLite database connections.
///
/// Since connections are opened in dedicated background isolates, this class
/// must be safe to pass to different isolates.
///
/// How databases are opened is platform specific. For this reason, this class
/// can't be extended directly. To customize how databases are opened across
/// platforms, prefer using [SqliteOptions]. If that class doesn't provide the
/// degree of customization you need, you can also subclass platform-specific
/// connection factory implementations:
///
///  - On native platforms, extend [NativeSqliteOpenFactory].
///  - When compiling for the web, extend [WebSqliteOpenFactory].
sealed class SqliteOpenFactory {
  final String path;

  SqliteOpenFactory._({required this.path});

  /// Creates a default open factory opening databases at the given path with
  /// specified options.
  ///
  /// This will return a [NativeSqliteOpenFactory] on native platforms and a
  /// [WebSqliteOpenFactory] when compiling for the web.
  factory SqliteOpenFactory({
    required String path,
    SqliteOptions options = const SqliteOptions(),
  }) {
    return platform.createDefaultOpenFactory(path, options);
  }

  /// Pragma statements to run on newly opened connections to configure them.
  List<String> pragmaStatements(SqliteOpenOptions options);
}

/// The superclass for all connection factories.
///
/// By keeping this class internal, we can safely assert that all connection
/// factories on native and web platforms extend [NativeSqliteOpenFactory] and
/// [WebSqliteOpenFactory], respectively.
@internal
abstract base class InternalOpenFactory extends SqliteOpenFactory {
  final SqliteOptions sqliteOptions;

  InternalOpenFactory({
    required super.path,
    this.sqliteOptions = const SqliteOptions(),
  }) : super._();
}

final class SqliteOpenOptions {
  /// Whether this is the primary write connection for the database.
  final bool primaryConnection;

  /// Whether this connection is read-only.
  final bool readOnly;

  /// Name used in debug logs
  final String? debugName;

  const SqliteOpenOptions({
    required this.primaryConnection,
    required this.readOnly,
    this.debugName,
  });

  sqlite.OpenMode get openMode {
    if (primaryConnection) {
      return sqlite.OpenMode.readWriteCreate;
    } else if (readOnly) {
      return sqlite.OpenMode.readOnly;
    } else {
      return sqlite.OpenMode.readWrite;
    }
  }
}
