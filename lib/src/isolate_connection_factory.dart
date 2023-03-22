import 'sqlite_connection_impl.dart';
import 'sqlite_connection.dart';
import 'mutex.dart';
import 'port_channel.dart';
import 'sqlite_open_factory.dart';

class IsolateConnectionFactory {
  SqliteOpenFactory openFactory;
  SerializedMutex mutex;
  SerializedPortClient upstreamPort;

  IsolateConnectionFactory(
      {required this.openFactory,
      required this.mutex,
      required this.upstreamPort});

  SqliteConnection open({String? debugName, bool readOnly = false}) {
    return SqliteConnectionImpl(
        openFactory: openFactory,
        mutex: mutex.open(),
        upstreamPort: upstreamPort,
        readOnly: readOnly,
        debugName: debugName,
        primary: false);
  }
}
