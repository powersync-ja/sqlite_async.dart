export 'stub_sqlite_database.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) './native/native_sqlite_database.dart'
    // ignore: uri_does_not_exist
    if (dart.library.html) './web/web_sqlite_database.dart';
