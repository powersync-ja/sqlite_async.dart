import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

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
  ReceivePort receivePort = ReceivePort();
  bool closed = false;
  int _nextId = 1;

  Map<int, Completer<Object?>> handlers = HashMap();

  ParentPortClient() {
    final initCompleter = Completer<SendPort>.sync();
    sendPortFuture = initCompleter.future;
    sendPortFuture.then((value) {
      sendPort = value;
    });
    receivePort.listen((message) {
      if (message is _InitMessage) {
        assert(!initCompleter.isCompleted);
        initCompleter.complete(message.port);
      } else if (message is _PortChannelResult) {
        final handler = handlers.remove(message.requestId);
        assert(handler != null);
        if (message.success) {
          handler!.complete(message.result);
        } else {
          handler!.completeError(message.error, message.stackTrace);
        }
      } else if (message == _closeMessage) {
        close();
      }
    }, onError: (e) {
      if (!initCompleter.isCompleted) {
        initCompleter.completeError(e);
      }

      close();
    }, onDone: () {
      if (!initCompleter.isCompleted) {
        initCompleter.completeError(ClosedException());
      }
      close();
    });
  }

  Future<void> get ready async {
    await sendPortFuture;
  }

  void _cancelAll(Object error) {
    var handlers = this.handlers;
    this.handlers = {};
    for (var message in handlers.values) {
      message.completeError(error);
    }
  }

  @override
  Future<T> post<T>(Object message) async {
    if (closed) {
      throw ClosedException();
    }
    var completer = Completer<T>.sync();
    var id = _nextId++;
    handlers[id] = completer;
    final port = sendPort ?? await sendPortFuture;
    port.send(_RequestMessage(id, message, null));
    return await completer.future;
  }

  @override
  void fire(Object message) async {
    if (closed) {
      throw ClosedException();
    }
    final port = sendPort ?? await sendPortFuture;
    port.send(_FireMessage(message));
  }

  RequestPortServer server() {
    return RequestPortServer(receivePort.sendPort);
  }

  void close() async {
    if (!closed) {
      closed = true;

      receivePort.close();
      _cancelAll(const ClosedException());
    }
  }

  tieToIsolate(Isolate isolate) {
    isolate.addOnExitListener(receivePort.sendPort, response: _closeMessage);
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
  final ReceivePort receivePort = ReceivePort();
  int _nextId = 1;
  bool closed = false;

  final Map<int, Completer<Object?>> handlers = HashMap();

  ChildPortClient(this.sendPort) {
    receivePort.listen((message) {
      if (message is _PortChannelResult) {
        final handler = handlers.remove(message.requestId);
        assert(handler != null);
        if (message.success) {
          handler!.complete(message.result);
        } else {
          handler!.completeError(message.error, message.stackTrace);
        }
      }
    });
  }

  @override
  Future<T> post<T>(Object message) async {
    if (closed) {
      throw const ClosedException();
    }
    var completer = Completer<T>.sync();
    var id = _nextId++;
    handlers[id] = completer;
    sendPort.send(_RequestMessage(id, message, receivePort.sendPort));
    return await completer.future;
  }

  @override
  void fire(Object message) {
    if (closed) {
      throw ClosedException();
    }
    sendPort.send(_FireMessage(message));
  }

  void _cancelAll(Object error) {
    var handlers = HashMap<int, Completer<Object?>>.from(this.handlers);
    this.handlers.clear();
    for (var message in handlers.values) {
      message.completeError(error);
    }
  }

  void close() {
    closed = true;
    _cancelAll(const ClosedException());
    receivePort.close();
  }
}

class RequestPortServer {
  final SendPort port;

  RequestPortServer(this.port);

  open(Future<Object?> Function(Object? message) handle) {
    return PortServer.forSendPort(port, handle);
  }
}

class PortServer {
  final ReceivePort _receivePort = ReceivePort();
  final Future<Object?> Function(Object? message) handle;
  final SendPort? replyPort;

  PortServer(this.handle) : replyPort = null {
    _init();
  }

  PortServer.forSendPort(SendPort port, this.handle) : replyPort = port {
    port.send(_InitMessage(_receivePort.sendPort));
    _init();
  }

  SendPort get sendPort {
    return _receivePort.sendPort;
  }

  SerializedPortClient client() {
    return SerializedPortClient(sendPort);
  }

  void close() {
    _receivePort.close();
  }

  void _init() {
    _receivePort.listen((request) async {
      if (request is _FireMessage) {
        handle(request.message);
      } else if (request is _RequestMessage) {
        if (request.id == 0) {
          // Fire and forget
          handle(request.message);
        } else {
          final replyPort = request.reply ?? this.replyPort;
          try {
            var result = await handle(request.message);
            replyPort!.send(_PortChannelResult.success(request.id, result));
          } catch (e, stacktrace) {
            replyPort!
                .send(_PortChannelResult.error(request.id, e, stacktrace));
          }
        }
      }
    });
  }
}

const _closeMessage = '_Close';

class _InitMessage {
  final SendPort port;

  _InitMessage(this.port);
}

class _FireMessage {
  final Object message;

  const _FireMessage(this.message);
}

class _RequestMessage {
  final int id;
  final Object message;
  final SendPort? reply;

  _RequestMessage(this.id, this.message, this.reply);
}

class ClosedException implements Exception {
  const ClosedException();
}

class _PortChannelResult<T> {
  final int requestId;
  final bool success;
  final T? _result;
  final Object? _error;
  final StackTrace? stackTrace;

  const _PortChannelResult.success(this.requestId, T result)
      : success = true,
        _error = null,
        stackTrace = null,
        _result = result;
  const _PortChannelResult.error(this.requestId, Object error,
      [this.stackTrace])
      : success = false,
        _result = null,
        _error = error;

  T get value {
    if (success) {
      return _result as T;
    } else {
      if (_error != null && stackTrace != null) {
        Error.throwWithStackTrace(_error!, stackTrace!);
      } else {
        throw _error!;
      }
    }
  }

  T get result {
    assert(success);
    return _result as T;
  }

  Object get error {
    assert(!success);
    return _error!;
  }
}
