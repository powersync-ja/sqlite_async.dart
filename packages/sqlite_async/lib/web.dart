/// Exposes interfaces implemented by database implementations on the web.
///
/// These expose methods allowing database instances to be shared across web
/// workers.
library;

export 'src/web/connection.dart';
export 'src/web/web_sqlite_open_factory.dart';
