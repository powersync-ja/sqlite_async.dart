import 'dart:async';
import 'dart:io';

import 'package:sqlite_async/sqlite_async.dart';

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp('sqlite-close-');
  final path = '${directory.path}/example.db';
  final reader = SqliteDatabase(path: path);
  final otherClient = SqliteDatabase(path: path);
  final snapshotStarted = Completer<void>();
  final releaseSnapshot = Completer<void>();
  Future<void>? reading;
  Future<void>? closing;
  try {
    await reader.execute('CREATE TABLE example (value INTEGER NOT NULL)');
    await reader.execute('INSERT INTO example VALUES (42)');
    await otherClient.get('SELECT 1');
    reading = reader.readTransaction((snapshot) async {
      await snapshot.get('SELECT value FROM example');
      snapshotStarted.complete();
      await releaseSnapshot.future;
    });
    await snapshotStarted.future;
    closing = otherClient.close();
    // Let close request exclusive access before the snapshot needs a writer.
    await Future<void>.delayed(Duration.zero);
    // Commit output before releasing its input snapshot.
    await reader.writeTransaction(
      (writer) => writer.execute('UPDATE example SET value = 43'),
      lockTimeout: const Duration(seconds: 1),
    );
    releaseSnapshot.complete();
    await reading;
    await closing;
    final row = await reader.get('SELECT value FROM example');
    stdout.writeln(
        'The snapshot completed. The stored value is ${row['value']}.');
  } on AbortException {
    stderr.writeln(
        'Deadlock: close reserved the writer and waited for the snapshot.');
    stderr.writeln(
        'The snapshot needed that writer. The timeout aborted its write.');
    exitCode = 1;
  } finally {
    // Release the snapshot before close can finish on the affected version.
    if (!releaseSnapshot.isCompleted) releaseSnapshot.complete();
    await reading;
    await closing;
    await otherClient.close();
    await reader.close();
    await directory.delete(recursive: true);
  }
}
