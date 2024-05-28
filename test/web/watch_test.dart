@TestOn('browser')
import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

import '../utils/test_utils_impl.dart';
import '../watch_test.dart';

final testUtils = TestUtils();

void main() {
  // Shared tests for watch
  group('Web Query Watch Tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    /// Can't use testUtils instance here since it requires spawnHybridUri
    /// which is not available when declaring tests
    generateSourceTableTests(['sqlite3.wasm'], (String sqlitePath) async {
      final db =
          SqliteDatabase.withFactory(await testUtils.testFactory(path: path));
      await db.initialize();
      return db;
    });
  });
}
