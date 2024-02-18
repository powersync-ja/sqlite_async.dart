/// This is an example of a database worker script
/// Custom database logic can be achieved by implementing this template
/// This file needs to be compiled to JavaScript with the command:
///   dart compile js -O4 lib/src/web/worker/db_worker.dart -o build/db_worker.js
/// The output should then be included in each project's `web` directory
library;

import 'dart:js_interop';

import 'package:sqlite3/wasm.dart';
import 'package:sqlite3_web/sqlite3_web.dart';

import 'worker_utils.dart';

void main() {
  WebSqlite.workerEntrypoint(controller: _AsyncSqliteController());
}

final class _AsyncSqliteController extends DatabaseController {
  @override
  Future<WorkerDatabase> openDatabase(WasmSqlite3 sqlite3, String vfs) async {
    final db = sqlite3.open('/app.db', vfs: vfs);
    setupCommonWorkerDB(db);

    return _AsyncSqliteDatabase(database: db);
  }

  @override
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request) {
    throw UnimplementedError();
  }
}

class _AsyncSqliteDatabase extends WorkerDatabase {
  @override
  final CommonDatabase database;

  _AsyncSqliteDatabase({required this.database});

  @override
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request) {
    // todo: This could be used to handle things like only giving one tab
    // access to the database at the time.
    throw UnimplementedError();
  }
}
