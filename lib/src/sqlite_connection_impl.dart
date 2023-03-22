import 'dart:async';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'isolate_completer.dart';
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

  @override
  final Stream<UpdateNotification>? updates;
  final PortClient _dbIsolate = PortClient();
  final String? debugName;
  final bool readOnly;

  SqliteConnectionImpl(
      {required SqliteOpenFactory openFactory,
      required Mutex mutex,
      required SendPort upstreamPort,
      this.updates,
      this.debugName,
      this.readOnly = false,
      bool primary = false})
      : _writeMutex = mutex {
    _open(openFactory, primary: primary, upstreamPort: upstreamPort);
  }

  Future<void> get ready async {
    await _dbIsolate.ready;
  }

  Future<void> _open(SqliteOpenFactory openFactory,
      {required bool primary, required SendPort upstreamPort}) async {
    await _connectionMutex.lock(() async {
      var isolate = await Isolate.spawn(
          _sqliteConnectionIsolate,
          _SqliteConnectionParams(
              openFactory: openFactory,
              port: upstreamPort,
              primary: primary,
              portServer: _dbIsolate.server(),
              readOnly: readOnly),
          debugName: debugName,
          paused: true);
      _dbIsolate.tieToIsolate(isolate);
      isolate.resume(isolate.pauseCapability!);

      await _dbIsolate.ready;
    });
  }

  bool get locked {
    return _connectionMutex.locked;
  }

  /// For internal use only
  Future<T> lock<T>(Future<T> Function() callback, {Duration? timeout}) async {
    return _connectionMutex.lock(callback, timeout: timeout);
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout}) async {
    // Private lock to synchronize this with other statements on the same connection,
    // to ensure that transactions aren't interleaved.
    return _connectionMutex.lock(() async {
      final ctx = _TransactionContext(_dbIsolate);
      try {
        return await callback(ctx);
      } finally {
        await ctx.close();
      }
    }, timeout: lockTimeout);
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout}) async {
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
        final ctx = _TransactionContext(_dbIsolate);
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
      throw AssertionError('Transaction closed');
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

  close() {
    _closed = true;
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
  final port = params.port;
  if (!params.primary) {
    // Wait until the primary connection has been initialized.
    // The primary connection is responsible for configuring journal mode,
    // running migrations, and other setup.
    var initialized = IsolateResult<void>();
    port.send(['init-db', initialized.completer]);
    await initialized.future;
  }
  final db = await params.openFactory.open(SqliteOpenOptions(
      primaryConnection: params.primary, readOnly: params.readOnly));

  final server = params.portServer;
  final commandPort = ReceivePort();

  Set<String> updatedTables = {};
  int? txId;
  Object? txError;

  db.updates.listen((event) {
    updatedTables.add(event.tableName);
  });
  server.init((data) async {
    if (data is _SqliteIsolateClose) {
      if (txId != null) {
        try {
          db.execute('ROLLBACK');
        } catch (e) {
          // Ignore
        }
        txId = null;
        txError = null;
        throw AssertionError(
            'Transaction must be closed within the read or write lock');
      }
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
        // Any statement after the first error will also error, until the
        // transaction is aborted.
        throw txError!;
      } else if (data.sql == 'COMMIT') {
        txId = null;
      }
      try {
        final result = db.select(data.sql, data.args);
        if (updatedTables.isNotEmpty) {
          port.send(['update', updatedTables]);
          updatedTables = {};
        }
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
        if (updatedTables.isNotEmpty) {
          port.send(['update', updatedTables]);
          updatedTables = {};
        }
      }
    }
  });

  commandPort.listen((data) async {});
}

class _SqliteConnectionParams {
  final PortServer portServer;
  final bool readOnly;

  final SendPort port;
  final bool primary;
  final SqliteOpenFactory openFactory;

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
