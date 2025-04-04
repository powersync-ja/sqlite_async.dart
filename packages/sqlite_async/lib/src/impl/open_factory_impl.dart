export 'stub_sqlite_open_factory.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) '../native/native_sqlite_open_factory.dart'
    // ignore: uri_does_not_exist
    if (dart.library.js_interop) '../web/web_sqlite_open_factory.dart';
