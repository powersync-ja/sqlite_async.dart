import 'package:sqlite_async/sqlite_async.dart';

final db = SqliteDatabase(
    path: 'test',
    options: SqliteOptions(
        webSqliteOptions: WebSqliteOptions(
            wasmUri: 'sqlite3.wasm', workerUri: 'drift.worker.js')));
