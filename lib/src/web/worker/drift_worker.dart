/// This is an example of a database worker script
/// Custom database logic can be achieved by implementing this template
/// This file needs to be compiled to JavaScript with the command:
///   dart compile js -O4 lib/src/web/worker/drift_worker.dart -o build/drift_worker.js
/// The output should then be included in each project's `web` directory
library;

import 'package:sqlite_async/drift.dart';
import 'package:sqlite_async/sqlite3_common.dart';

/// Use this function to register any custom DB functionality
/// which requires direct access to the connection
void setupDatabase(CommonDatabase database) {
  setupCommonWorkerDB(database);
}

void main() {
  WasmDatabase.workerMainForOpen(
    setupAllDatabases: setupDatabase,
  );
}
