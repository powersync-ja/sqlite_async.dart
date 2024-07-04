/// This is an example of a database worker script
/// Custom database logic can be achieved by implementing this template
/// This file needs to be compiled to JavaScript with the command:
///   dart compile js -O4 lib/src/web/worker/db_worker.dart -o build/db_worker.js
/// The output should then be included in each project's `web` directory
library;

import 'package:sqlite3_web/sqlite3_web.dart';
import 'worker_utils.dart';

void main() {
  WebSqlite.workerEntrypoint(controller: AsyncSqliteController());
}
