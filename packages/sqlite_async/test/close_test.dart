@TestOn('!browser')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

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
      final directory =
          await Directory.systemTemp.createTemp('recovery-close-');
      final root = SqliteDatabase(path: '${directory.path}/app.db');
      final scheduled = SqliteDatabase(path: '${directory.path}/app.db');
      await root.execute('CREATE TABLE test_rows (value INTEGER NOT NULL)');
      await root.execute('INSERT INTO test_rows VALUES (42)');
      await scheduled.get('SELECT 1');
      final callerZone = Zone.current;
      final snapshotStarted = Completer<void>();
      final continueSnapshot = Completer<void>();
      final reading = root.readTransaction((tx) async {
        await tx.get('SELECT value FROM test_rows');
        snapshotStarted.complete();
        await continueSnapshot.future;
        await callerZone.run(
          () => root.writeTransaction(
            (writer) => writer.execute('UPDATE test_rows SET value = 43'),
            lockTimeout: const Duration(seconds: 1),
          ),
        );
        expect(await tx.get('SELECT value FROM test_rows'), {'value': 42});
      });
      await snapshotStarted.future;
      final closing = scheduled.close();
      await Future<void>.delayed(Duration.zero);
      continueSnapshot.complete();
      try {
        await reading;
        await closing.timeout(const Duration(seconds: 5));
        expect(await root.get('SELECT value FROM test_rows'), {'value': 43});
        expect(await root.get('PRAGMA integrity_check'), {
          'integrity_check': 'ok',
        });
      } finally {
        await closing;
        await root.close();
        await directory.delete(recursive: true);
      }
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
      try {
        await pendingWrite.timeout(const Duration(seconds: 5));
        expect(closed, isFalse);
        await expectLater(
          database.getAutoCommit(),
          throwsA(isA<AbortException>()),
        );
      } finally {
        releaseWriter.complete();
        await writing;
        await closing.timeout(const Duration(seconds: 5));
      }
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
      try {
        await queuedRead.timeout(const Duration(seconds: 5));
        await expectLater(db.get('SELECT 2'), throwsAbortException);
      } finally {
        releaseReader.complete();
        await reading;
        await closing.timeout(const Duration(seconds: 5));
      }
    });

    test('the standalone example completes without a deadlock', () async {
      final library = await Isolate.resolvePackageUri(
          Uri.parse('package:sqlite_async/sqlite_async.dart'));
      final package = File.fromUri(library!).parent.parent;
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'example/close_deadlock/bin/close_deadlock.dart'],
        workingDirectory: package.path,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('The stored value is 43.'));
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
