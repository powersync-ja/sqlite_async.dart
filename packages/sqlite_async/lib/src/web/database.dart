import 'dart:async';
import 'dart:developer';
import 'dart:js_interop';

import 'package:sqlite3/common.dart';
import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:sqlite_async/src/utils/profiler.dart';
import 'package:sqlite_async/src/web/database/broadcast_updates.dart';
import 'package:sqlite_async/web.dart';
import '../impl/context.dart';
import 'protocol.dart';
import 'web_mutex.dart';

class WebDatabase
    with SqliteQueries, SqliteDatabaseMixin
    implements SqliteDatabase, WebSqliteConnection {
  final Database _database;
  final Mutex? _mutex;
  final bool profileQueries;

  @override
  final Stream<UpdateNotification> updates;

  /// For persistent databases that aren't backed by a shared worker, we use
  /// web broadcast channels to forward local update events to other tabs.
  final BroadcastUpdates? broadcastUpdates;

  @override
  bool closed = false;

  WebDatabase(
    this._database,
    this._mutex, {
    required this.profileQueries,
    required this.updates,
    this.broadcastUpdates,
  });

  @override
  Future<void> close() async {
    await _database.dispose();
    closed = true;
  }

  @override
  Future<void> get closedFuture => _database.closed;

  @override
  Future<bool> getAutoCommit() async {
    final response = await _database.customRequest(
        CustomDatabaseMessage(CustomDatabaseMessageKind.getAutoCommit));
    return (response as JSBoolean?)?.toDart ?? false;
  }

  @override
  Future<void> initialize() {
    return Future.value();
  }

  @override
  Future<void> get isInitialized => initialize();

  @override

  /// Not relevant for web.
  Never isolateConnectionFactory() {
    throw UnimplementedError();
  }

  @override

  /// Not supported on web. There is only 1 connection.
  int get maxReaders => throw UnimplementedError();

  @override

  /// Not relevant for web.
  Never get openFactory => throw UnimplementedError();

  @override
  Future<WebDatabaseEndpoint> exposeEndpoint() async {
    final endpoint = await _database.additionalConnection();

    return (
      connectPort: endpoint.$1,
      connectName: endpoint.$2,
      lockName: switch (_mutex) {
        MutexImpl(:final resolvedIdentifier) => resolvedIdentifier,
        _ => null,
      },
    );
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) async {
    // Since there is only a single physical connection per database on the web,
    // we can't enable concurrent readers to a writer. Even supporting multiple
    // readers alone isn't safe, since these readers could start read
    // transactions where we need to block other tabs from sending `BEGIN` and
    // `COMMIT` statements if they were to start their own transactions.
    return _lockInternal(
      (unscoped) => ScopedReadContext.assumeReadLock(unscoped, callback),
      lockTimeout: lockTimeout,
      debugContext: debugContext,
      flush: false,
    );
  }

  @override
  Future<T> writeTransaction<T>(
      Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout,
      bool? flush}) {
    return _lockInternal(
      (context) {
        return ScopedWriteContext.assumeWriteLock(
          context,
          (ctx) async {
            return await ctx.writeTransaction(callback);
          },
        );
      },
      flush: flush ?? true,
      lockTimeout: lockTimeout,
    );
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext, bool? flush}) async {
    return await _lockInternal(
      (unscoped) {
        return ScopedWriteContext.assumeWriteLock(unscoped, callback);
      },
      flush: flush ?? true,
      debugContext: debugContext,
      lockTimeout: lockTimeout,
    );
  }

  Future<T> _lockInternal<T>(
    Future<T> Function(_UnscopedContext) callback, {
    required bool flush,
    Duration? lockTimeout,
    String? debugContext,
  }) async {
    if (_mutex case var mutex?) {
      return await mutex.lock(timeout: lockTimeout, () async {
        final context = _UnscopedContext(this, null);
        try {
          return await callback(context);
        } finally {
          if (flush) {
            await this.flush();
          }
        }
      });
    } else {
      final abortTrigger = switch (lockTimeout) {
        null => null,
        final duration => Future.delayed(duration),
      };

      return await _database.requestLock(abortTrigger: abortTrigger,
          (token) async {
        final context = _UnscopedContext(this, token);
        try {
          return await callback(context);
        } finally {
          if (flush) {
            await this.flush();
          }
        }
      });
    }
  }

  @override
  Future<void> flush() async {
    await isInitialized;
    return _database.fileSystem.flush();
  }

  @override
  Future<T> withAllConnections<T>(
      Future<T> Function(
              SqliteWriteContext writer, List<SqliteReadContext> readers)
          block) {
    return writeLock((_) => block(this, []));
  }
}

final class _UnscopedContext extends UnscopedContext {
  final WebDatabase _database;

  /// If this context is scoped to a lock on the database, the [LockToken] from
  /// `package:sqlite3_web`.
  ///
  /// This token needs to be passed to queries to run them. While a lock token
  /// exists on the database, all queries not passing that token are blocked.
  final LockToken? _lock;

  final TimelineTask? _task;

  /// Whether statements should be rejected if the database is not in an
  /// autocommit state.
  bool _checkInTransaction = false;

  _UnscopedContext(this._database, this._lock)
      : _task = _database.profileQueries ? TimelineTask() : null;

  @override
  bool get closed => _database.closed;

  @override
  Future<T> computeWithDatabase<T>(
      Future<T> Function(CommonDatabase db) compute) {
    // Can't be implemented: The database may live on another worker.
    throw UnimplementedError();
  }

  @override
  Future<Row> get(String sql, [List<Object?> parameters = const []]) async {
    final results = await getAll(sql, parameters);
    return results.first;
  }

  @override
  Future<ResultSet> getAll(String sql,
      [List<Object?> parameters = const []]) async {
    return _task.timeAsync(
      'getAll',
      sql: sql,
      parameters: parameters,
      () async {
        return await wrapSqliteException(() async {
          final result = await _database._database.select(
            sql,
            parameters: parameters,
            token: _lock,
            checkInTransaction: _checkInTransaction,
          );
          return result.result;
        });
      },
    );
  }

  @override
  Future<bool> getAutoCommit() async {
    return _database.getAutoCommit();
  }

  @override
  Future<Row?> getOptional(String sql,
      [List<Object?> parameters = const []]) async {
    final results = await getAll(sql, parameters);
    return results.firstOrNull;
  }

  @override
  Future<ResultSet> execute(String sql, [List<Object?> parameters = const []]) {
    return _task.timeAsync('execute', sql: sql, parameters: parameters, () {
      return wrapSqliteException(() async {
        final result = await _database._database.select(
          sql,
          parameters: parameters,
          token: _lock,
          checkInTransaction: _checkInTransaction,
        );
        return result.result;
      });
    });
  }

  @override
  Future<void> executeBatch(String sql, List<List<Object?>> parameterSets) {
    return _task.timeAsync('executeBatch', sql: sql, () {
      return wrapSqliteException(() async {
        for (final set in parameterSets) {
          // use execute instead of select to avoid transferring rows from the
          // worker to this context.
          await _database._database.execute(
            sql,
            parameters: set,
            token: _lock,
            checkInTransaction: _checkInTransaction,
          );
        }
      });
    });
  }

  @override
  Future<void> executeMultiple(String sql,
      [List<Object?> parameters = const []]) {
    return _task.timeAsync('executeMultiple', sql: sql, () {
      return wrapSqliteException(() async {
        await _database._database.execute(
          sql,
          parameters: parameters,
          token: _lock,
          checkInTransaction: _checkInTransaction,
        );
      });
    });
  }

  @override
  UnscopedContext interceptOutermostTransaction() {
    // All execute calls done in the callback will be checked for the
    // autocommit state
    return _UnscopedContext(_database, _lock).._checkInTransaction = true;
  }
}

/// Throws SqliteException if the Remote Exception is a SqliteException
Future<T> wrapSqliteException<T>(Future<T> Function() callback) async {
  try {
    return await callback();
  } on RemoteException catch (ex) {
    if (ex.exception case final serializedCause?) {
      throw serializedCause;
    }

    if (ex.message.contains('Database is not in a transaction')) {
      throw SqliteException(
          0, "Transaction rolled back by earlier statement. Cannot execute.");
    }

    // Older versions of package:sqlite_web reported SqliteExceptions as strings
    // only.
    if (ex.toString().contains('SqliteException')) {
      RegExp regExp = RegExp(r'SqliteException\((\d+)\)');
      throw SqliteException(
          int.parse(regExp.firstMatch(ex.message)?.group(1) ?? '0'),
          ex.message);
    }
    rethrow;
  }
}
