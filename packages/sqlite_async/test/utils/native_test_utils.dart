import 'dart:async';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/src/database.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'abstract_test_utils.dart';

const defaultSqlitePath = 'libsqlite3.so.0';

class TestUtils extends AbstractTestUtils {
  @override
  String dbPath() {
    return d.path('test.db');
  }

  @override
  Future<void> cleanDb({required String path}) async {
    try {
      await File(path).delete();
    } on PathNotFoundException {
      // Not an issue
    }
    try {
      await File("$path-shm").delete();
    } on PathNotFoundException {
      // Not an issue
    }
    try {
      await File("$path-wal").delete();
    } on PathNotFoundException {
      // Not an issue
    }
  }

  @override
  Future<CommonDatabase> openDatabaseForSingleConnection() async {
    return sqlite3.openInMemory();
  }
}
