@TestOn('browser')
library;

import 'dart:async';

import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite_async/sqlite3_web_worker.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/web.dart';
import 'package:test/test.dart';

import '../utils/web_test_utils.dart';

void main() {
  late String sqliteUri;

  setUpAll(() async {
    final utils = TestUtils();
    sqliteUri = await utils.sqliteWasmUri;
  });

  _MockWebFactory factory(String path, DatabaseImplementation impl) {
    final fakeWorkers = FakeWorkerEnvironment();
    WebSqlite.workerEntrypoint(
      controller: AsyncSqliteController(),
      environment: fakeWorkers,
    );
    addTearDown(fakeWorkers.close);

    return _MockWebFactory(fakeWorkers, sqliteUri,
        path: path, implementation: impl);
  }

  test('can share broadcast updates', () async {
    // Emulate two workers from different tabs opening the same database. They
    // should share updates over a broadcast channel.
    final a = SqliteDatabase.withFactory(
        factory('test.db', DatabaseImplementation.opfsWithExternalLocks));
    final b = SqliteDatabase.withFactory(
            factory('test.db', DatabaseImplementation.opfsWithExternalLocks))
        as WebSqliteConnection;

    final didEmitOnB =
        expectLater(b.updates, emits(UpdateNotification({'tbl'})));
    await a.execute('CREATE TABLE tbl (c TEXT NOT NULL)');
    await a.execute('INSERT INTO tbl (c) VALUES (?)', ['testing']);
    await didEmitOnB;

    // The broadcast update should also apply when the database is shared.
    final clonedB =
        await WebSqliteConnection.connectToEndpoint(await b.exposeEndpoint());
    final didEmitOnClone =
        expectLater(clonedB.updates, emits(UpdateNotification({'tbl'})));
    await a.execute('INSERT INTO tbl (c) VALUES (?)', ['testing more']);
    await didEmitOnClone;
  });

  test('uses locks when each tab has its own connection', () async {
    final a = SqliteDatabase.withFactory(
        factory('test.db', DatabaseImplementation.indexedDbUnsafeWorker));
    final b = SqliteDatabase.withFactory(
        factory('test.db', DatabaseImplementation.indexedDbUnsafeWorker));

    final hasWriteLockOnA = Completer<void>();
    final completeWriteLockOnA = Completer<void>();
    a.writeLock((ctx) async {
      hasWriteLockOnA.complete();
      await completeWriteLockOnA.future;
    });

    await hasWriteLockOnA.future;

    var hasWriteLockOnB = false;
    final lockBCompleted = b.writeLock((_) async {
      hasWriteLockOnB = true;
    });

    await pumpEventQueue();
    expect(hasWriteLockOnB, isFalse);
    completeWriteLockOnA.complete();

    await lockBCompleted;
    expect(hasWriteLockOnB, isTrue);
  });
}

final class _MockWebFactory extends WebSqliteOpenFactory {
  final FakeWorkerEnvironment env;
  final DatabaseImplementation implementation;
  final String wasmModule;

  _MockWebFactory(this.env, this.wasmModule,
      {required super.path,
      this.implementation = DatabaseImplementation.inMemoryShared})
      : super(
          sqliteOptions: SqliteOptions(
            // Ensure openWebSqlite isn't cached across factory instances.
            webSqliteOptions: WebSqliteOptions(wasmUri: 'sqlite_${_counter++}'),
          ),
        );

  @override
  Future<WebSqlite> openWebSqlite(WebSqliteOptions options) async {
    return WebSqlite.open(
      workers: _FakeWorkerConnector(env),
      wasmModule: wasmModule,
      handleCustomRequest: handleCustomRequest,
    );
  }

  @override
  Future<ConnectToRecommendedResult> connectToWorker(
      WebSqlite sqlite, String name) async {
    // We always open an in-memory database, but then pretend it's a different
    // implementation so that WebSqliteOpenFactory installs locks or broadcast
    // channels.
    final database =
        await sqlite.connect(path, DatabaseImplementation.inMemoryShared);

    return ConnectToRecommendedResult(
      database: database,
      features: FeatureDetectionResult(
        missingFeatures: [],
        existingDatabases: [],
        availableImplementations: [],
      ),
      implementation: implementation,
    );
  }

  static var _counter = 0;
}

final class _FakeWorkerConnector implements WorkerConnector {
  final FakeWorkerEnvironment _env;

  _FakeWorkerConnector(this._env);

  @override
  WorkerHandle? spawnDedicatedWorker() {
    return _env;
  }

  @override
  WorkerHandle? spawnSharedWorker() {
    return _env;
  }
}
