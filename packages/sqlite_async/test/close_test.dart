@TestOn('!browser')
library;

import 'dart:async';
import 'dart:io';

import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import 'utils/test_utils_impl.dart';

final testUtils = TestUtils();

void main() {
  group('Close Tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    tearDown(() async {
      await testUtils.cleanDb(path: path);
    });

    createTables(SqliteDatabase db) async {
      await db.writeTransaction((tx) async {
        await tx.execute(
            'CREATE TABLE test_data(id INTEGER PRIMARY KEY AUTOINCREMENT, description TEXT)');
      });
    }

    test('another client can close during a read snapshot', () async {
      final a = SqliteDatabase(path: path);
      final b = SqliteDatabase(path: path);

      await a.get('SELECT 1');
      await b.get('SELECT 1');

      await a.readTransaction((tx) async {
        await b.close();
      });
      await a.close();
    });

    test('close drains its active writer and aborts its queued writer',
        () async {
      final directory = await Directory.systemTemp.createTemp('writer-close-');
      final database = SqliteDatabase(path: '${directory.path}/app.db');
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      await database.execute('CREATE TABLE test_rows (value INTEGER NOT NULL)');
      final writerStarted = Completer<void>();
      final releaseWriter = Completer<void>();
      final writing = database.writeTransaction((tx) async {
        await tx.execute('INSERT INTO test_rows VALUES (42)');
        writerStarted.complete();
        await releaseWriter.future;
        await tx.execute('UPDATE test_rows SET value = 43');
      });
      await writerStarted.future;
      final pendingWrite = expectLater(
        database.execute('INSERT INTO test_rows VALUES (99)'),
        throwsA(isA<AbortException>()),
      );
      var closed = false;
      final closing = database.close().then((_) => closed = true);
      await pendingWrite;
      expect(closed, isFalse);
      await expectLater(
        database.getAutoCommit(),
        throwsA(isA<AbortException>()),
      );
      releaseWriter.complete();
      await writing;
      await closing;
      final reopened = SqliteDatabase(path: '${directory.path}/app.db');
      addTearDown(reopened.close);
      expect(await reopened.get('SELECT value FROM test_rows'), {'value': 43});
      expect(await reopened.get('PRAGMA integrity_check'), {
        'integrity_check': 'ok',
      });
    });

    test('close aborts queued readers and rejects new requests', () async {
      final db = SqliteDatabase(
        path: path,
        options: const SqliteOptions(maxReaders: 1),
      );
      await createTables(db);
      final readerStarted = Completer<void>();
      final releaseReader = Completer<void>();
      final reading = db.readTransaction((tx) async {
        await tx.get('SELECT 1');
        readerStarted.complete();
        await releaseReader.future;
      });
      await readerStarted.future;
      final queuedRead = expectLater(db.get('SELECT 1'), throwsAbortException);
      final closing = db.close();
      await queuedRead;
      await expectLater(db.get('SELECT 2'), throwsAbortException);
      releaseReader.complete();
      await reading;
      await closing;
    });

    test('Open and close', () async {
      // Test that the journal files are properly deleted after closing.
      // If the write connection is closed before the read connections, that is
      // not the case.

      final db = await testUtils.setupDatabase(path: path);
      await createTables(db);

      await db.execute(
          'INSERT INTO test_data(description) VALUES(?)', ['Test Data']);
      await db.getAll('SELECT * FROM test_data');

      expect(await File('$path-wal').exists(), equals(true));
      expect(await File('$path-shm').exists(), equals(true));

      await db.close();

      expect(await File(path).exists(), equals(true));

      expect(await File('$path-wal').exists(), equals(false));
      expect(await File('$path-shm').exists(), equals(false));

      expect(await File('$path-journal').exists(), equals(false));
    });
  });
}
