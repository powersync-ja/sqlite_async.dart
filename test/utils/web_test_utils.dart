import 'dart:async';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';
import 'abstract_test_utils.dart';

class TestUtils extends AbstractTestUtils {
  late final Future<void> _isInitialized;
  late SqliteOptions? webOptions = null;

  TestUtils() {
    _isInitialized = init();
  }

  Future<void> init() async {
    if (webOptions != null) {
      return;
    }

    final channel = spawnHybridUri('/test/server/asset_server.dart');
    final port = await channel.stream.first as int;

    final sqliteWasm = Uri.parse('http://localhost:$port/sqlite3.wasm');
    final sqliteDrift = Uri.parse('http://localhost:$port/drift_worker.js');

    print('sqlite4' + sqliteWasm.toString());

    webOptions = SqliteOptions(
        webSqliteOptions: WebSqliteOptions(
            wasmUri: sqliteWasm.toString(), workerUri: sqliteDrift.toString()));
  }

  @override
  Future<void> cleanDb({required String path}) async {}

  @override
  TestDefaultSqliteOpenFactory testFactory(
      {String? path,
      String? sqlitePath,
      SqliteOptions options = const SqliteOptions.defaults()}) {
    return super.testFactory(path: path, options: webOptions!);
  }

  @override
  Future<SqliteDatabase> setupDatabase({String? path}) {
    return super.setupDatabase(path: path);
  }

  @override
  List<String> findSqliteLibraries() {
    return [];
  }
}
