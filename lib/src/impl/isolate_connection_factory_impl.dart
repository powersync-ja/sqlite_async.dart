export 'stub_isolate_connection_factory.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) '../native/native_isolate_connection_factory.dart'
    // ignore: uri_does_not_exist
    if (dart.library.html) '../web/web_isolate_connection_factory.dart';
