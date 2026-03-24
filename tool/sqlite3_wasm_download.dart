/// Downloads sqlite3.wasm
library;

import 'dart:convert';
import 'dart:io';

void main() async {
  // Create assets directory if it doesn't exist
  final assetsDir = Directory('assets');
  if (!await assetsDir.exists()) {
    await assetsDir.create();
  }

  final sqliteFilename = 'sqlite3.wasm';
  final sqlitePath = 'assets/$sqliteFilename';

  // Download sqlite3.wasm
  final version = await findSqliteVersion();
  final sqliteUrl =
      'https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-${version}/sqlite3.wasm';

  await downloadFile(sqliteUrl, sqlitePath);
}

Future<String> findSqliteVersion() async {
  final lockFileLines = File(
    'pubspec.lock',
  ).openRead().transform(utf8.decoder).transform(const LineSplitter());
  final versionRegex = RegExp(r'version: "(.+)"');

  var isReadingSqlite3Entry = false;

  await for (final line in lockFileLines) {
    if (line.endsWith(' sqlite3:')) {
      isReadingSqlite3Entry = true;
    }

    if (isReadingSqlite3Entry) {
      if (versionRegex.firstMatch(line) case final match?) {
        return match.group(1)!;
      }
    }
  }

  throw StateError(
    'Could not find version for sqlite3 package in pubspec.lock',
  );
}

Future<void> downloadFile(String url, String savePath) async {
  print('Downloading: $url');
  var httpClient = HttpClient();
  var request = await httpClient.getUrl(Uri.parse(url));
  var response = await request.close();
  if (response.statusCode == HttpStatus.ok) {
    var file = File(savePath);
    await response.pipe(file.openWrite());
    httpClient.close();
  } else {
    print(
      'Failed to download file: ${response.statusCode} ${response.reasonPhrase}',
    );
  }
}
