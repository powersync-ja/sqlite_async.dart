import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

class PortClient {
  late Future<SendPort> sendPort;
  ReceivePort receivePort = ReceivePort();
  bool closed = false;
  int _nextId = 1;

  Map<int, Completer<Object?>> handlers = HashMap();

  PortClient() {
    final initCompleter = Completer<SendPort>();
    sendPort = initCompleter.future;
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
    await sendPort;
  }

  _cancelAll(Object error) {
    var handlers = this.handlers;
    this.handlers = {};
    for (var message in handlers.values) {
      message.completeError(error);
    }
  }

  Future<T> post<T>(Object message) async {
    if (closed) {
      throw ClosedException();
    }
    var completer = Completer<T>();
    var id = _nextId++;
    handlers[id] = completer;
    (await sendPort).send(_RequestMessage(id, message));
    return await completer.future;
  }

  PortServer server() {
    return PortServer(receivePort.sendPort);
  }

  close() async {
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

class PortServer {
  SendPort port;
  late ReceivePort receivePort;
  late Future<Object?> Function(Object? message) handle;

  PortServer(this.port);

  void init(Future<Object?> Function(Object? message) handle) {
    this.handle = handle;
    receivePort = ReceivePort();
    port.send(_InitMessage(receivePort.sendPort));
    receivePort.listen((message) async {
      final request = message as _RequestMessage;
      try {
        var result = await handle(request.message);
        port.send(_PortChannelResult.success(request.id, result));
      } catch (e, stacktrace) {
        port.send(_PortChannelResult.error(request.id, e, stacktrace));
      }
    });
  }
}

const _closeMessage = '_Close';

class _InitMessage {
  final SendPort port;

  _InitMessage(this.port);
}

class _RequestMessage {
  final int id;
  final Object message;

  _RequestMessage(this.id, this.message);
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
