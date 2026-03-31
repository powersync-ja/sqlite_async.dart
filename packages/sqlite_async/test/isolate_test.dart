@TestOn('!browser')
library;

import 'dart:async';
import 'dart:isolate';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

void main() {
  group('Isolate Tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    tearDown(() async {
      await testUtils.cleanDb(path: path);
    });

    test('Basic Isolate usage', () async {
      final db = await testUtils.setupDatabase(path: path);
      await db.execute('CREATE TABLE test(name TEXT);');

      await Isolate.run(() async {
        final db = SqliteDatabase(path: path);
        await db.execute('INSERT INTO test (name) VALUES (?)',
            ['separate instance from isolate']);
        await db.close();
      });
      expect(await db.get('SELECT name FROM test'),
          equals({'name': 'separate instance from isolate'}));
    });

    test('instances coordinate on write locks', () async {
      final db = await testUtils.setupDatabase(path: path);
      var otherIsolateReceivedWriteLock = Completer<void>();

      final port = ReceivePort();
      addTearDown(port.close);
      port.listen((_) => otherIsolateReceivedWriteLock.complete());

      final hasLocalWriteLock = Completer();
      final completeLocalWriteLock = Completer();
      db.writeLock((_) async {
        hasLocalWriteLock.complete();
        await completeLocalWriteLock.future;
      });

      await hasLocalWriteLock.future;

      // Try to obtain write lock in other isolate, which should not work until
      // we release it here.
      _spawnIsolateAcquiringWriteLock(path, port.sendPort);

      expect(otherIsolateReceivedWriteLock.isCompleted, isFalse);
      await pumpEventQueue();
      expect(otherIsolateReceivedWriteLock.isCompleted, isFalse);

      completeLocalWriteLock.complete();
      await otherIsolateReceivedWriteLock.future;
    });
  });
}

void _spawnIsolateAcquiringWriteLock(String path, SendPort notifyWhenObtained) {
  Isolate.run(() async {
    final db = SqliteDatabase(path: path);
    await db.writeLock((_) async {
      notifyWhenObtained.send('did obtain write lock');
    });
    await db.close();
  });
}
