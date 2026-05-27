/// This is an example of a database worker script
/// Custom database logic can be achieved by implementing this template.
///
/// This file needs to be compiled to JavaScript via `dart compile js`:
///
/// ```
/// dart compile js \
///   lib/src/web/worker/db_worker.dart \
///   -o build/db_worker.js \
///   -O4
///   -Dsqlite3.dartbigints=false
/// ```
///
/// The output should then be included in each project's `web` directory.
///
/// Disabling `sqlite3.dartbigints` as a compile-time option reduces the size of
/// the worker by disabling support for [BigInt] values which are implemented in
/// Dart. The worker still supports native JavaScript bigint values, so this
/// doesn't affect functionality.
library;

import 'package:sqlite3_web/sqlite3_web.dart';
import 'worker_utils.dart';

void main() {
  WebSqlite.workerEntrypoint(controller: AsyncSqliteController());
}
