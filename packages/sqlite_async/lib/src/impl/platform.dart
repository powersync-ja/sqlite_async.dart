export 'platform_stub.dart'
    if (dart.library.js_interop) 'platform_web.dart'
    if (dart.library.io) 'platform_native.dart';
