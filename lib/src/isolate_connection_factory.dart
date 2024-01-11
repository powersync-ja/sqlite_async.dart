// This follows the pattern from here: https://stackoverflow.com/questions/58710226/how-to-import-platform-specific-dependency-in-flutter-dart-combine-web-with-an
// To conditionally export an implementation for either web or "native" platforms
// The sqlite library uses dart:ffi which is not supported on web

import 'package:sqlite_async/src/isolate_connection_factory/abstract_isolate_connection_factory.dart';
export 'package:sqlite_async/src/isolate_connection_factory/abstract_isolate_connection_factory.dart';

import '../definitions.dart';
import './isolate_connection_factory/stub_isolate_connection_factory.dart' as base
    if (dart.library.io) './isolate_connection_factory/native/isolate_connection_factory.dart'
    if (dart.library.html) './isolate_connection_factory/web/isolate_connection_factory.dart';


class IsolateConnectionFactory extends AbstractIsolateConnectionFactory {
  late AbstractIsolateConnectionFactory adapter;
  
    IsolateConnectionFactory({
    required SqliteOpenFactory openFactory,
  }) {
    super.openFactory = openFactory;
    adapter = base.IsolateConnectionFactory(openFactory: openFactory);
  }


  @override
  SqliteConnection open({String? debugName, bool readOnly = false}) {
      return adapter.open(debugName: debugName, readOnly: readOnly);
  }

}