import 'dart:async';
import 'dart:isolate';

import 'package:async/async.dart';

final class WorkItem {
  final SendPort completePort;
  final Object? Function() task;

  WorkItem(this.completePort, this.task);
}

final class IsolateWorker {
  final Isolate isolate;
  final SendPort sendCommands;

  IsolateWorker._(this.isolate, this.sendCommands);

  Future<T> run<T>(FutureOr<T> Function() task) async {
    final port = ReceivePort();
    sendCommands.send(WorkItem(port.sendPort, task));

    return (await Result.release(port.first.then((r) => r as Result<Object?>)))
        as T;
  }

  void close() => isolate.kill();

  static Future<IsolateWorker> spawn() async {
    final receiveSendPort = ReceivePort();
    final isolate = await Isolate.spawn(_entrypoint, receiveSendPort.sendPort);
    final port = (await receiveSendPort.first) as SendPort;

    return IsolateWorker._(isolate, port);
  }

  static void _entrypoint(SendPort sendPort) async {
    final receiveTasks = ReceivePort('receive tasks');
    sendPort.send(receiveTasks.sendPort);

    await for (final WorkItem(:completePort, :task)
        in receiveTasks.cast<WorkItem>()) {
      final result = await runZonedGuarded(
        () => Result.capture(Future.sync(task)),
        (Object e, StackTrace s) {
          completePort.send(ErrorResult(e, s));
        },
      );

      completePort.send(result);
    }
  }
}
