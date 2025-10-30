import 'dart:async';
import 'dart:collection';

typedef SendPort = Never;
typedef ReceivePort = Never;
typedef Isolate = Never;

Never _stub() {
  throw UnsupportedError('Isolates are not supported on this platform');
}

abstract class PortClient {
  Future<T> post<T>(Object message);
  void fire(Object message);

  factory PortClient.parent() {
    return ParentPortClient();
  }

  factory PortClient.child(SendPort upstream) {
    return ChildPortClient(upstream);
  }
}

class ParentPortClient implements PortClient {
  late Future<SendPort> sendPortFuture;
  SendPort? sendPort;
  bool closed = false;

  Map<int, Completer<Object?>> handlers = HashMap();

  ParentPortClient();

  Future<void> get ready async {
    await sendPortFuture;
  }

  @override
  Future<T> post<T>(Object message) async {
    _stub();
  }

  @override
  void fire(Object message) async {
    _stub();
  }

  RequestPortServer server() {
    _stub();
  }

  void close() {
    _stub();
  }

  void tieToIsolate(Isolate isolate) {
    _stub();
  }
}

class SerializedPortClient {
  final SendPort sendPort;

  SerializedPortClient(this.sendPort);

  ChildPortClient open() {
    return ChildPortClient(sendPort);
  }
}

class ChildPortClient implements PortClient {
  final SendPort sendPort;
  ReceivePort get receivePort => _stub();
  bool closed = false;

  final Map<int, Completer<Object?>> handlers = HashMap();

  ChildPortClient(this.sendPort);

  @override
  Future<T> post<T>(Object message) async {
    _stub();
  }

  @override
  void fire(Object message) {
    _stub();
  }

  void close() {
    _stub();
  }
}

class RequestPortServer {
  final SendPort port;

  RequestPortServer(this.port);

  PortServer open(Future<Object?> Function(Object? message) handle) {
    _stub();
  }
}

class PortServer {
  final Future<Object?> Function(Object? message) handle;
  final SendPort? replyPort;

  PortServer(this.handle) : replyPort = null;

  PortServer.forSendPort(SendPort port, this.handle) : replyPort = port;

  SendPort get sendPort {
    _stub();
  }

  SerializedPortClient client() {
    return SerializedPortClient(sendPort);
  }

  void close() {
    _stub();
  }
}

class ClosedException implements Exception {
  const ClosedException();

  @override
  String toString() {
    return 'ClosedException';
  }
}

class IsolateError extends Error {
  final Object cause;
  final String? isolateDebugName;

  IsolateError({required this.cause, this.isolateDebugName});

  @override
  String toString() {
    if (isolateDebugName != null) {
      return 'IsolateError in $isolateDebugName: $cause';
    } else {
      return 'IsolateError: $cause';
    }
  }
}
