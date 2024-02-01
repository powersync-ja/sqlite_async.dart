import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import 'asset_server.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final directory = Directory.systemTemp
      .createTempSync('sqlite_dart_web')
      .resolveSymbolicLinksSync();

  // Copy sqlite3.wasm file expected by the worker
  final sqliteOutputPath = p.join(directory, 'sqlite3.wasm');
  await File('assets/sqlite3.wasm').copy(sqliteOutputPath);

  final driftWorkerPath = p.join(directory, 'drift_worker.js');
  // And compile worker code
  final process = await Process.run(Platform.executable, [
    'compile',
    'js',
    '-o',
    driftWorkerPath,
    '-O0',
    'lib/src/web/worker/drift_worker.dart',
  ]);
  if (process.exitCode != 0) {
    fail('Could not compile worker');
  }

  print('compiled worker');

  final server = await HttpServer.bind('localhost', 0);

  final handler = const Pipeline()
      .addMiddleware(cors())
      .addHandler(createStaticHandler(directory));
  io.serveRequests(server, handler);

  channel.sink.add(server.port);
  await channel.stream.listen(null).asFuture<void>().then<void>((_) async {
    print('closing server');
    await server.close();
    await Directory(directory).delete();
  });
}
