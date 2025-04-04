/// Downloads sqlite3.wasm
library;

import 'dart:io';

final sqliteUrl =
    'https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-2.4.3/sqlite3.wasm';

void main() async {
  // Create assets directory if it doesn't exist
  final assetsDir = Directory('assets');
  if (!await assetsDir.exists()) {
    await assetsDir.create();
  }

  final sqliteFilename = 'sqlite3.wasm';
  final sqlitePath = 'assets/$sqliteFilename';

  // Download sqlite3.wasm
  await downloadFile(sqliteUrl, sqlitePath);
}

Future<void> downloadFile(String url, String savePath) async {
  print('Downloading: $url');
  var httpClient = HttpClient();
  var request = await httpClient.getUrl(Uri.parse(url));
  var response = await request.close();
  if (response.statusCode == HttpStatus.ok) {
    var file = File(savePath);
    await response.pipe(file.openWrite());
  } else {
    print(
        'Failed to download file: ${response.statusCode} ${response.reasonPhrase}');
  }
}
