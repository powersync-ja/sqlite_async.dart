export 'stub_mutex.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) '../native/native_isolate_mutex.dart'
    // ignore: uri_does_not_exist
    if (dart.library.js_interop) '../web/web_mutex.dart';
