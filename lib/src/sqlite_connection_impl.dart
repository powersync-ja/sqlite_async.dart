import 'dart:async';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'database_utils.dart';
import 'mutex.dart';
import 'port_channel.dart';
import 'sqlite_connection.dart';
import 'sqlite_open_factory.dart';
import 'sqlite_queries.dart';
import 'update_notification.dart';

typedef TxCallback<T> = Future<T> Function(sqlite.Database db);

/// Implements a SqliteConnection using a separate isolate for the database
/// operations.
class SqliteConnectionImpl with SqliteQueries implements SqliteConnection {
  /// Private to this connection
  final SimpleMutex _connectionMutex = SimpleMutex();
  final Mutex _writeMutex;

  /// Must be a broadcast stream
  @override
  final Stream<UpdateNotification>? updates;
  final ParentPortClient _isolateClient = ParentPortClient();
  late final Isolate _isolate;
  final String? debugName;
  final bool readOnly;

  SqliteConnectionImpl(
      {required SqliteOpenFactory<sqlite.Database> openFactory,
      required Mutex mutex,
      required SerializedPortClient upstreamPort,
      this.updates,
      this.debugName,
      this.readOnly = false,
      bool primary = false})
      : _writeMutex = mutex {
    _open(openFactory, primary: primary, upstreamPort: upstreamPort);
  }

  Future<void> get ready async {
    await _isolateClient.ready;
  }

  @override
  bool get closed {
    return _isolateClient.closed;
  }

  Future<void> _open(SqliteOpenFactory<sqlite.Database> openFactory,
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
    });
  }

  @override
  Future<void> close() async {
    await _connectionMutex.lock(() async {
      if (readOnly) {
        await _isolateClient.post(const _SqliteIsolateConnectionClose());
      } else {
        // In some cases, disposing a write connection lock the database.
        // We use the lock here to avoid "database is locked" errors.
        await _writeMutex.lock(() async {
          await _isolateClient.post(const _SqliteIsolateConnectionClose());
        });
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
      final ctx = _TransactionContext(_isolateClient);
      try {
        return await callback(ctx);
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
        final ctx = _TransactionContext(_isolateClient);
        try {
          return await callback(ctx);
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

class _TransactionContext implements SqliteWriteContext {
  final PortClient _sendPort;
  bool _closed = false;
  final int ctxId = _nextCtxId++;

  _TransactionContext(this._sendPort);

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
      var future = _sendPort.post<sqlite.ResultSet>(
          _SqliteIsolateStatement(ctxId, sql, parameters, readOnly: false));

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
  Future<T> computeWithDatabase<T>(
      Future<T> Function(sqlite.Database db) compute) async {
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
}

void _sqliteConnectionIsolate(_SqliteConnectionParams params) async {
  final client = params.port.open();

  if (!params.primary) {
    // Wait until the primary connection has been initialized.
    // The primary connection is responsible for configuring journal mode,
    // running migrations, and other setup.
    await client.post(const InitDb());
  }

  final db = await params.openFactory.open(SqliteOpenOptions(
      primaryConnection: params.primary, readOnly: params.readOnly));

  runZonedGuarded(() async {
    await _sqliteConnectionIsolateInner(params, client, db);
  }, (error, stack) {
    db.dispose();
    throw error;
  });
}

Future<void> _sqliteConnectionIsolateInner(_SqliteConnectionParams params,
    ChildPortClient client, sqlite.Database db) async {
  final server = params.portServer;
  final commandPort = ReceivePort();

  Timer? updateDebouncer;
  Set<String> updatedTables = {};
  int? txId;
  Object? txError;

  void maybeFireUpdates() {
    if (updatedTables.isNotEmpty) {
      client.fire(UpdateNotification(updatedTables));
      updatedTables.clear();
      updateDebouncer?.cancel();
      updateDebouncer = null;
    }
  }

  db.updates.listen((event) {
    updatedTables.add(event.tableName);

    // This handles two cases:
    // 1. Update arrived after _SqliteIsolateClose (not sure if this could happen).
    // 2. Long-running _SqliteIsolateClosure that should fire updates while running.
    updateDebouncer ??=
        Timer(const Duration(milliseconds: 10), maybeFireUpdates);
  });

  server.open((data) async {
    if (data is _SqliteIsolateClose) {
      if (txId != null) {
        try {
          db.execute('ROLLBACK');
        } catch (e) {
          // Ignore
        }
        txId = null;
        txError = null;
        throw sqlite.SqliteException(
            0, 'Transaction must be closed within the read or write lock');
      }
      // We would likely have received updates by this point - fire now.
      maybeFireUpdates();
      return null;
    } else if (data is _SqliteIsolateStatement) {
      if (data.sql == 'BEGIN' || data.sql == 'BEGIN IMMEDIATE') {
        if (txId != null) {
          // This will error on db.select
        }
        txId = data.ctxId;
      } else if (txId != null && txId != data.ctxId) {
        // Locks should prevent this from happening
        throw AssertionError('Mixed transactions: $txId and ${data.ctxId}');
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
          txError = err;
        }
        rethrow;
      }
    } else if (data is _SqliteIsolateClosure) {
      try {
        return await data.cb(db);
      } finally {
        maybeFireUpdates();
      }
    } else if (data is _SqliteIsolateConnectionClose) {
      db.dispose();
      return null;
    } else {
      throw ArgumentError('Unknown data type $data');
    }
  });

  commandPort.listen((data) async {});
}

class _SqliteConnectionParams {
  final RequestPortServer portServer;
  final bool readOnly;

  final SerializedPortClient port;
  final bool primary;
  final SqliteOpenFactory<sqlite.Database> openFactory;

  _SqliteConnectionParams(
      {required this.openFactory,
      required this.portServer,
      required this.port,
      required this.readOnly,
      required this.primary});
}

class _SqliteIsolateStatement {
  final int ctxId;
  final String sql;
  final List<Object?> args;
  final bool readOnly;

  _SqliteIsolateStatement(this.ctxId, this.sql, this.args,
      {this.readOnly = false});
}

class _SqliteIsolateClosure {
  final TxCallback cb;

  _SqliteIsolateClosure(this.cb);
}

class _SqliteIsolateClose {
  final int ctxId;

  const _SqliteIsolateClose(this.ctxId);
}

class _SqliteIsolateConnectionClose {
  const _SqliteIsolateConnectionClose();
}
