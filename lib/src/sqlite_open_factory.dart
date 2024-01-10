export './open_factory/abstract_open_factory.dart';

export './open_factory/stub_sqlite_open_factory.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) './open_factory/native/native_sqlite_open_factory.dart'
    // ignore: uri_does_not_exist
    if (dart.library.html) './open_factory/web/web_sqlite_open_factory.dart';
