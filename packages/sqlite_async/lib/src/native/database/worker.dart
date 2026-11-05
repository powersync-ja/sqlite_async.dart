import 'dart:async';
import 'dart:isolate';

import 'package:async/async.dart';
import 'package:sqlite3_connection_pool/sqlite3_connection_pool.dart';

/// A long-lived isolate running work items sent as closures.
///
/// Ideally, we should be able to use [Isolate.run] for this purpose. In
/// benchmarks however, this seems to be substantially faster than spawning new
/// isolates.
final class IsolateWorker {
  final Isolate _isolate;

  final ReceivePort _receiveResponses;
  final SendPort _sendCommands;

  final Map<int, Completer<Object?>> _outstandingWorkItems = {};
  int _nextWorkItem = 0;
  var _closeRequested = false;
  late final Future<void> _closeAcknowledged;

  IsolateWorker._(this._isolate, this._sendCommands, this._receiveResponses) {
    _closeAcknowledged = _receiveResponses.listen((Object? message) {
      if (message == null) {
        // Null message is the exit listener registered on the isolate.

        for (final pending in _outstandingWorkItems.values) {
          // This really shouldn't happen, but it's better than not having a future
          // that doesn't complete.
          pending.completeError(StateError('Worker closed'));
        }
        _outstandingWorkItems.clear();

        _receiveResponses.close();
        return;
      }

      final WorkResult(:id, :result) = message as WorkResult;
      if (_outstandingWorkItems.remove(id) case final completer?) {
        switch (result) {
          case ValueResult(:final value):
            completer.complete(value);
          case ErrorResult(:final error, :final stackTrace):
            completer.completeError(error, stackTrace);
        }
      }
    }).asFuture();
  }

  /// Runs [task] on the worker isolate, passing a connection obtained from
  /// [connection].
  ///
  /// The caller must hold a lease on [connection] and must not use it until
  /// the returned future completes.
  Future<T> run<T>(
    ShareableAsyncConnection connection,
    FutureOr<T> Function(PoolConnection) task,
  ) async {
    if (_closeRequested) throw StateError('Isolate worker closed');

    final id = _nextWorkItem++;
    final completer = _outstandingWorkItems[id] = Completer();

    _sendCommands
        .send(WorkItem(id, _receiveResponses.sendPort, connection, task));
    return (await completer.future) as T;
  }

  Future<void> close() {
    _closeRequested = true;
    _isolate.kill();

    return _closeAcknowledged;
  }

  static Future<IsolateWorker> spawn() async {
    final receiveSendPort = ReceivePort();
    final receiveResponses = ReceivePort('isolate worker');
    final isolate = await Isolate.spawn(
      _entrypoint,
      receiveSendPort.sendPort,
      onExit: receiveResponses.sendPort,
    );

    final port = (await receiveSendPort.first) as SendPort;

    return IsolateWorker._(isolate, port, receiveResponses);
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
  final ShareableAsyncConnection connection;
  final Object? Function(PoolConnection) task;

  WorkItem(this.id, this.completePort, this.connection, this.task);

  Future<void> handle() async {
    final lease = connection.obtainConnection();
    if (lease == null) {
      // This can happen in rare cases if the parent isolate exits after
      // sending the request to this child isolate.
      completePort.send(WorkResult(
          id,
          ErrorResult(
              StateError('Parent isolate closed'), StackTrace.current)));
      return;
    }

    void complete(Result<Object?> result) {
      // This is harmless if called multiple times.
      lease.returnLease();
      completePort.send(WorkResult(id, result));
    }

    final result = await runZonedGuarded(
      () => Result.capture(Future.sync(() => task(lease.unsafeRawConnection))),
      (Object e, StackTrace s) => complete(ErrorResult(e, s)),
    );

    if (result != null) {
      // For errors, we would have already sent the response.
      complete(result);
    }
  }
}

final class WorkResult {
  final int id;
  final Result<Object?> result;

  WorkResult(this.id, this.result);
}
