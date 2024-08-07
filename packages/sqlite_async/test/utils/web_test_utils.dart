import 'dart:async';
import 'dart:html';

import 'package:js/js.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';
import 'abstract_test_utils.dart';

@JS('URL.createObjectURL')
external String _createObjectURL(Blob blob);

class TestUtils extends AbstractTestUtils {
  late Future<void> _isInitialized;
  late final SqliteOptions webOptions;

  TestUtils() {
    _isInitialized = _init();
  }

  Future<void> _init() async {
    final channel = spawnHybridUri('/test/server/worker_server.dart');
    final port = await channel.stream.first as int;
    final sqliteWasmUri = 'http://localhost:$port/sqlite3.wasm';
    // Cross origin workers are not supported, but we can supply a Blob
    var sqliteUri = 'http://localhost:$port/db_worker.js';

    final blob = Blob(
        <String>['importScripts("$sqliteUri");'], 'application/javascript');
    sqliteUri = _createObjectURL(blob);

    webOptions = SqliteOptions(
        webSqliteOptions: WebSqliteOptions(
            wasmUri: sqliteWasmUri.toString(), workerUri: sqliteUri));
  }

  @override
  Future<void> cleanDb({required String path}) async {}

  @override
  Future<TestDefaultSqliteOpenFactory> testFactory(
      {String? path,
      String? sqlitePath,
      List<String> initStatements = const [],
      SqliteOptions options = const SqliteOptions.defaults()}) async {
    await _isInitialized;
    return super.testFactory(
        path: path, options: webOptions, initStatements: initStatements);
  }

  @override
  Future<SqliteDatabase> setupDatabase(
      {String? path,
      List<String> initStatements = const [],
      int maxReaders = SqliteDatabase.defaultMaxReaders}) async {
    await _isInitialized;
    return super.setupDatabase(path: path);
  }

  @override
  List<String> findSqliteLibraries() {
    return ['sqlite3.wasm'];
  }
}
