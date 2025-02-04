import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:sqlite_async/sqlite3_wasm.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show Blob, BlobPart, BlobPropertyBag;
import 'abstract_test_utils.dart';

@JS('URL.createObjectURL')
external String _createObjectURL(Blob blob);

String? _dbPath;

class TestSqliteOpenFactory extends TestDefaultSqliteOpenFactory {
  TestSqliteOpenFactory(
      {required super.path, super.sqliteOptions, super.sqlitePath = ''});

  @override
  Future<CommonDatabase> openDatabaseForSingleConnection() async {
    final sqlite = await WasmSqlite3.loadFromUrl(
        Uri.parse(sqliteOptions.webSqliteOptions.wasmUri));
    sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);

    return sqlite.openInMemory();
  }
}

class TestUtils extends AbstractTestUtils {
  late Future<void> _isInitialized;
  late final SqliteOptions webOptions;

  TestUtils() {
    _isInitialized = _init();
  }

  Future<void> _init() async {
    final channel = spawnHybridUri('/test/server/worker_server.dart');
    final port = (await channel.stream.first as num).toInt();
    final sqliteWasmUri = 'http://localhost:$port/sqlite3.wasm';
    // Cross origin workers are not supported, but we can supply a Blob
    var sqliteUri = 'http://localhost:$port/db_worker.js';

    final blob = Blob(<BlobPart>['importScripts("$sqliteUri");'.toJS].toJS,
        BlobPropertyBag(type: 'application/javascript'));
    sqliteUri = _createObjectURL(blob);

    webOptions = SqliteOptions(
        webSqliteOptions: WebSqliteOptions(
            wasmUri: sqliteWasmUri.toString(), workerUri: sqliteUri));
  }

  @override
  String dbPath() {
    if (_dbPath case final path?) {
      return path;
    }

    final created = _dbPath = 'test-db/${Random().nextInt(1 << 31)}/test.db';
    addTearDown(() {
      // Pick a new path for the next test.
      _dbPath = null;
    });

    return created;
  }

  @override
  Future<void> cleanDb({required String path}) async {}

  @override
  Future<TestDefaultSqliteOpenFactory> testFactory(
      {String? path,
      String sqlitePath = '',
      List<String> initStatements = const [],
      SqliteOptions options = const SqliteOptions.defaults()}) async {
    await _isInitialized;
    return TestSqliteOpenFactory(
      path: path ?? dbPath(),
      sqlitePath: sqlitePath,
      sqliteOptions: webOptions,
    );
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
