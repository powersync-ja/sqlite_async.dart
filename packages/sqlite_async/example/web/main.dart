import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:sqlite_async/sqlite_async.dart';

void main() {
  globalContext['open'] = (String path) {
    return Future(() async {
      final db = SqliteDatabase(
        path: path,
        options: SqliteOptions(
          webSqliteOptions: WebSqliteOptions(
            wasmUri:
                'https://cdn.jsdelivr.net/npm/@powersync/dart-wasm-bundles@latest/dist/sqlite3.wasm',
            workerUri: 'worker.dart.js',
          ),
        ),
      );
      await db.initialize();
      return db.toJSBox;
    }).toJS;
  }.toJS;

  globalContext['write_lock'] = (JSBoxedDartObject db) {
    final hasLock = Completer<void>();
    final completer = Completer<void>();

    (db.toDart as SqliteDatabase).writeLock((_) async {
      print('has write lock!');
      hasLock.complete();
      await completer.future;
    });

    return hasLock.future.then((_) => completer.toJSBox).toJS;
  }.toJS;

  globalContext['release_lock'] = (JSBoxedDartObject db) {
    (db.toDart as Completer<void>).complete();
  }.toJS;
}
