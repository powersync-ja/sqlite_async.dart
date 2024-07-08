import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_static/shelf_static.dart';
import 'package:stream_channel/stream_channel.dart';

import 'asset_server.dart';

Future<void> hybridMain(StreamChannel<Object?> channel) async {
  final directory = p.normalize(
      p.join(DartScript.self.pathToScriptDirectory, '../../../../assets'));

  final sqliteOutputPath = p.join(directory, 'sqlite3.wasm');

  if (!(await File(sqliteOutputPath).exists())) {
    throw AssertionError(
        'sqlite3.wasm file should be present in the ./assets folder');
  }

  final server = await HttpServer.bind('localhost', 0);

  final handler = const Pipeline()
      .addMiddleware(cors())
      .addHandler(createStaticHandler(directory));
  io.serveRequests(server, handler);

  channel.sink.add(server.port);
  await channel.stream.listen(null).asFuture<void>().then<void>((_) async {
    print('closing server');
    await server.close();
  });
}
