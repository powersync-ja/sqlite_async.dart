import 'dart:async';
import 'dart:developer';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/common/mutex.dart';
import 'package:sqlite_async/src/common/port_channel.dart';
import 'package:sqlite_async/src/native/native_isolate_mutex.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
import 'package:sqlite_async/src/update_notification.dart';
import 'package:sqlite_async/src/utils/profiler.dart';
import 'package:sqlite_async/src/utils/shared_utils.dart';

import '../../impl/context.dart';
import 'upstream_updates.dart';

typedef TxCallback<T> = Future<T> Function(CommonDatabase db);

/// Implements a SqliteConnection using a separate isolate for the database
/// operations.
class SqliteConnectionImpl
    with SqliteQueries, UpStreamTableUpdates
    implements SqliteConnection {
  /// Private to this connection
  final SimpleMutex _connectionMutex = SimpleMutex();
  final Mutex _writeMutex;

  /// Must be a broadcast stream
  @override
  late final Stream<UpdateNotification>? updates;
  final ParentPortClient _isolateClient = ParentPortClient();
  late final Isolate _isolate;
  final String? debugName;
  final bool readOnly;

  final bool profileQueries;
  bool _didOpenSuccessfully = false;

  SqliteConnectionImpl({
    required AbstractDefaultSqliteOpenFactory openFactory,
    required Mutex mutex,
    SerializedPortClient? upstreamPort,
    Stream<UpdateNotification>? updates,
    this.debugName,
    this.readOnly = false,
    bool primary = false,
  })  : _writeMutex = mutex,
        profileQueries = openFactory.sqliteOptions.profileQueries {
    this.upstreamPort = upstreamPort ?? listenForEvents();
    // Accept an incoming stream of updates, or expose one if not given.
    this.updates = updates ?? updatesController.stream;
    isInitialized =
        _open(openFactory, primary: primary, upstreamPort: this.upstreamPort);
  }

  Future<void> get ready async {
    await _isolateClient.ready;
  }

  @override
  bool get closed {
    return _isolateClient.closed;
  }

  _UnsafeContext _context() {
    return _UnsafeContext(
        _isolateClient, profileQueries ? TimelineTask() : null);
  }

  @override
  Future<bool> getAutoCommit() async {
    if (closed) {
      throw AssertionError('Closed');
    }
    // We use a _TransactionContext without a lock here.
    // It is safe to call this in the middle of another transaction.
    final ctx = _context();
    try {
      return await ctx.getAutoCommit();
    } finally {
      await ctx.close();
    }
  }

  Future<void> _open(AbstractDefaultSqliteOpenFactory openFactory,
      {required bool primary,
      required SerializedPortClient upstreamPort}) async {
    await _connectionMutex.lock(() async {
      _isolate = await Isolate.spawn(
          _sqliteConnectionIsolate,
          _SqliteConnectionParams(
              openFactory: openFactory,
              port: upstreamPort,
              primary: primary,
              portServer: _isolateClient.server(),
              readOnly: readOnly),
          debugName: debugName,
          paused: true);
      _isolateClient.tieToIsolate(_isolate);
      _isolate.resume(_isolate.pauseCapability!);
      await _isolateClient.ready;
      _didOpenSuccessfully = true;
    });
  }

  @override
  Future<void> close() async {
    eventsPort?.close();
    await _connectionMutex.lock(() async {
      if (_didOpenSuccessfully) {
        if (readOnly) {
          await _isolateClient.post(const _SqliteIsolateConnectionClose());
        } else {
          // In some cases, disposing a write connection lock the database.
          // We use the lock here to avoid "database is locked" errors.
          await _writeMutex.lock(() async {
            await _isolateClient.post(const _SqliteIsolateConnectionClose());
          });
        }
      }

      _isolate.kill();
    });
  }

  bool get locked {
    return _connectionMutex.locked;
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    // Private lock to synchronize this with other statements on the same connection,
    // to ensure that transactions aren't interleaved.
    return _connectionMutex.lock(() async {
      final ctx = _context();
      try {
        return await ScopedReadContext.assumeReadLock(ctx, callback);
      } finally {
        await ctx.close();
      }
    }, timeout: lockTimeout);
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    final stopWatch = lockTimeout == null ? null : (Stopwatch()..start());
    // Private lock to synchronize this with other statements on the same connection,
    // to ensure that transactions aren't interleaved.
    return await _connectionMutex.lock(() async {
      Duration? innerTimeout;
      if (lockTimeout != null && stopWatch != null) {
        innerTimeout = lockTimeout - stopWatch.elapsed;
        stopWatch.stop();
      }
      // DB lock so that only one write happens at a time
      return await _writeMutex.lock(() async {
        final ctx = _context();
        try {
          return await ScopedWriteContext.assumeWriteLock(ctx, callback);
        } finally {
          await ctx.close();
        }
      }, timeout: innerTimeout).catchError((error, stackTrace) {
        if (error is TimeoutException) {
          return Future<T>.error(TimeoutException(
              'Failed to acquire global write lock', lockTimeout));
        }
        return Future<T>.error(error, stackTrace);
      });
    }, timeout: lockTimeout);
  }
}

int _nextCtxId = 1;

final class _UnsafeContext extends UnscopedContext {
  final PortClient _sendPort;
  bool _closed = false;
  final int ctxId = _nextCtxId++;

  final TimelineTask? task;

  _UnsafeContext(this._sendPort, this.task);

  @override
  bool get closed {
    return _closed;
  }

  @override
  Future<sqlite.ResultSet> execute(String sql,
      [List<Object?> parameters = const []]) async {
    return getAll(sql, parameters);
  }

  @override
  Future<sqlite.ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) async {
    if (_closed) {
      throw sqlite.SqliteException(0, 'Transaction closed', null, sql);
    }
    try {
      var future = _sendPort.post<sqlite.ResultSet>(_SqliteIsolateStatement(
        ctxId,
        sql,
        parameters,
        readOnly: false,
        timelineTask: task?.pass(),
      ));

      return await future;
    } on sqlite.SqliteException catch (e) {
      if (e.resultCode == 8) {
        // SQLITE_READONLY
        throw sqlite.SqliteException(
            e.extendedResultCode,
            'attempt to write in a read-only transaction',
            null,
            e.causingStatement);
      } else {
        rethrow;
      }
    }
  }

  @override
  Future<bool> getAutoCommit() async {
    return await computeWithDatabase(
      (db) async {
        return db.autocommit;
      },
    );
  }

  @override
  Future<T> computeWithDatabase<T>(
      Future<T> Function(CommonDatabase db) compute) async {
    return _sendPort.post<T>(_SqliteIsolateClosure(compute));
  }

  @override
  Future<sqlite.Row> get(String sql,
      [List<Object?> parameters = const []]) async {
    final rows = await getAll(sql, parameters);
    return rows.first;
  }

  @override
  Future<sqlite.Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) async {
    final rows = await getAll(sql, parameters);
    return rows.isEmpty ? null : rows[0];
  }

  Future<void> close() async {
    _closed = true;
    await _sendPort.post(_SqliteIsolateClose(ctxId));
  }

  @override
  Future<void> executeBatch(String sql, List<List<Object?>> parameterSets) {
    return computeWithDatabase((db) async {
      final statement = db.prepare(sql, checkNoTail: true);
      try {
        for (var parameters in parameterSets) {
          statement.execute(parameters);
        }
      } finally {
        statement.dispose();
      }
    });
  }

  @override
  Future<void> executeMultiple(String sql) async {
    return computeWithDatabase((db) async {
      final statements = db.prepareMultiple(sql);
      try {
        for (var statement in statements) {
          statement.execute();
        }
      } finally {
        for (var statement in statements) {
          statement.dispose();
        }
      }
    });
  }
}

void _sqliteConnectionIsolate(_SqliteConnectionParams params) async {
  final client = params.port.open();

  if (!params.primary) {
    // Wait until the primary connection has been initialized.
    // The primary connection is responsible for configuring journal mode,
    // running migrations, and other setup.
    await client.post(const InitDb());
  }

  final db = params.openFactory.open(SqliteOpenOptions(
      primaryConnection: params.primary, readOnly: params.readOnly));

  runZonedGuarded(() async {
    await _sqliteConnectionIsolateInner(params, client, db);
  }, (error, stack) {
    db.dispose();
    throw error;
  });
}

Future<void> _sqliteConnectionIsolateInner(_SqliteConnectionParams params,
    ChildPortClient client, CommonDatabase db) async {
  final server = params.portServer;
  final commandPort = ReceivePort();

  db.updatedTables.listen((changedTables) {
    client.fire(UpdateNotification(changedTables));
  });

  int? txId;
  Object? txError;

  ResultSet runStatement(_SqliteIsolateStatement data) {
    if (data.sql == 'BEGIN' || data.sql == 'BEGIN IMMEDIATE') {
      if (txId != null) {
        // This will error on db.select
      }
      txId = data.ctxId;
    } else if (txId != null && txId != data.ctxId) {
      // Locks should prevent this from happening
      throw sqlite.SqliteException(
          0, 'Mixed transactions: $txId and ${data.ctxId}');
    } else if (data.sql == 'ROLLBACK') {
      // This is the only valid way to clear an error
      txError = null;
      txId = null;
    } else if (txError != null) {
      // Any statement (including COMMIT) after the first error will also error, until the
      // transaction is aborted.
      throw txError!;
    } else if (data.sql == 'COMMIT' || data.sql == 'END TRANSACTION') {
      txId = null;
    }
    try {
      final result = db.select(data.sql, mapParameters(data.args));
      return result;
    } catch (err) {
      if (txId != null) {
        if (db.autocommit) {
          // Transaction rolled back
          txError = sqlite.SqliteException(0,
              'Transaction rolled back by earlier statement: ${err.toString()}');
        } else {
          // Recoverable error
        }
      }
      rethrow;
    }
  }

  Future<Object?> handle(_RemoteIsolateRequest data, TimelineTask? task) async {
    switch (data) {
      case _SqliteIsolateClose():
        // This is a transaction close message
        if (txId != null) {
          if (!db.autocommit) {
            db.execute('ROLLBACK');
          }
          txId = null;
          txError = null;
          throw sqlite.SqliteException(
              0, 'Transaction must be closed within the read or write lock');
        }
        return null;
      case _SqliteIsolateStatement():
        return task.timeSync(
          'execute_remote',
          () => runStatement(data),
          sql: data.sql,
          parameters: data.args,
        );
      case _SqliteIsolateClosure():
        return await data.cb(db);
      case _SqliteIsolateConnectionClose():
        db.dispose();
        return null;
    }
  }

  server.open((data) async {
    if (data is! _RemoteIsolateRequest) {
      throw ArgumentError('Unknown data type $data');
    }

    final task = switch (data.timelineTask) {
      null => null,
      final id => TimelineTask.withTaskId(id),
    };

    return await handle(data, task);
  });

  commandPort.listen((data) async {});
}

sealed class _RemoteIsolateRequest {
  final int? timelineTask;

  const _RemoteIsolateRequest({required this.timelineTask});
}

class _SqliteConnectionParams {
  final RequestPortServer portServer;
  final bool readOnly;

  final SerializedPortClient port;
  final bool primary;
  final AbstractDefaultSqliteOpenFactory openFactory;

  _SqliteConnectionParams(
      {required this.openFactory,
      required this.portServer,
      required this.port,
      required this.readOnly,
      required this.primary});
}

class _SqliteIsolateStatement extends _RemoteIsolateRequest {
  final int ctxId;
  final String sql;
  final List<Object?> args;
  final bool readOnly;

  _SqliteIsolateStatement(this.ctxId, this.sql, this.args,
      {this.readOnly = false, super.timelineTask});
}

class _SqliteIsolateClosure extends _RemoteIsolateRequest {
  final TxCallback cb;

  _SqliteIsolateClosure(this.cb, {super.timelineTask});
}

class _SqliteIsolateClose extends _RemoteIsolateRequest {
  final int ctxId;

  const _SqliteIsolateClose(this.ctxId, {super.timelineTask});
}

class _SqliteIsolateConnectionClose extends _RemoteIsolateRequest {
  const _SqliteIsolateConnectionClose({super.timelineTask});
}
