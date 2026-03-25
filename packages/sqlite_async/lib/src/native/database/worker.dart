import 'dart:async';
import 'dart:isolate';

import 'package:async/async.dart';

/// A long-lived isolate running work items sent as closures.
///
/// Ideally, we should be able to use [Isolate.run] for this purpose. In
/// benchmarks however, this seems to be substantially faster than spawning new
/// isolates.
final class IsolateWorker {
  final Isolate _isolate;

  final ReceivePort _receiveResponses = ReceivePort('isolate worker');
  final SendPort _sendCommands;

  final Map<int, Completer<Object?>> _outstandingWorkItems = {};
  int _nextWorkItem = 0;

  IsolateWorker._(this._isolate, this._sendCommands) {
    _receiveResponses.listen((Object? message) {
      final WorkResult(:id, :result) = message as WorkResult;
      if (_outstandingWorkItems.remove(id) case final completer?) {
        switch (result) {
          case ValueResult(:final value):
            completer.complete(value);
          case ErrorResult(:final error, :final stackTrace):
            completer.completeError(error, stackTrace);
        }
      }
    });
  }

  Future<T> run<T>(FutureOr<T> Function() task) async {
    final id = _nextWorkItem++;
    final completer = _outstandingWorkItems[id] = Completer();

    _sendCommands.send(WorkItem(id, _receiveResponses.sendPort, task));
    return (await completer.future) as T;
  }

  void close() {
    _isolate.kill();
    for (final pending in _outstandingWorkItems.values) {
      // This really shouldn't happen, but it's better than not having a future
      // that doesn't complete.
      pending.completeError(StateError('Worker closed'));
    }
    _outstandingWorkItems.clear();
    _receiveResponses.close();
  }

  static Future<IsolateWorker> spawn() async {
    final receiveSendPort = ReceivePort();
    final isolate = await Isolate.spawn(_entrypoint, receiveSendPort.sendPort);
    final port = (await receiveSendPort.first) as SendPort;

    return IsolateWorker._(isolate, port);
  }

  static void _entrypoint(SendPort sendPort) async {
    final receiveTasks = ReceivePort('receive tasks');
    sendPort.send(receiveTasks.sendPort);

    await for (final item in receiveTasks.cast<WorkItem>()) {
      await item.handle();
    }
  }
}

final class WorkItem {
  final int id;
  final SendPort completePort;
  final Object? Function() task;

  WorkItem(this.id, this.completePort, this.task);

  Future<void> handle() async {
    final result = await runZonedGuarded(
      () => Result.capture(Future.sync(task)),
      (Object e, StackTrace s) {
        completePort.send(WorkResult(id, ErrorResult(e, s)));
      },
    );

    if (result != null) {
      // For errors, we would have already sent the response.
      completePort.send(WorkResult(id, result));
    }
  }
}

final class WorkResult {
  final int id;
  final Result<Object?> result;

  WorkResult(this.id, this.result);
}
