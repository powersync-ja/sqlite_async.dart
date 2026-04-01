import 'package:sqlite_async/sqlite_async.dart';
import 'package:test/test.dart';

export 'stub_test_utils.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) 'native_test_utils.dart'
    // ignore: uri_does_not_exist
    if (dart.library.js_interop) 'web_test_utils.dart';

TypeMatcher<AbortException> isAbortException() {
  return isA<AbortException>();
}

Matcher get throwsAbortException => throwsA(isAbortException());
