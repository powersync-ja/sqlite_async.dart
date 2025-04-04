import 'abstract_test_utils.dart';

class TestUtils extends AbstractTestUtils {
  @override
  String dbPath() {
    throw UnimplementedError();
  }

  @override
  Future<void> cleanDb({required String path}) {
    throw UnimplementedError();
  }

  @override
  List<String> findSqliteLibraries() {
    throw UnimplementedError();
  }
}
