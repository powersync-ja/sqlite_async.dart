import 'package:sqlite_async/sqlite_async.dart';

import '../common/sqlite_database.dart';

/// A database implementation that delegates everything to a single connection.
///
/// This doesn't provide an automatic connection pool or the web worker
/// management, but it can still be useful in cases like unit tests where those
/// features might not be necessary. Since only a single sqlite connection is
/// used internally, this also allows using in-memory databases.
final class SingleConnectionDatabase extends SqliteDatabaseImpl {
  final SqliteConnection connection;

  SingleConnectionDatabase(this.connection);

  @override
  Future<void> close() => connection.close();

  @override
  bool get closed => connection.closed;

  @override
  Future<bool> getAutoCommit() => connection.getAutoCommit();

  @override
  Future<void> get isInitialized => Future.value();

  @override
  int get maxReaders => 1;

  @override
  SqliteOpenFactory get openFactory => throw UnimplementedError();

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    return connection.readLock(callback,
        lockTimeout: lockTimeout, debugContext: debugContext);
  }

  @override
  Stream<UpdateNotification> get updates =>
      connection.updates ?? const Stream.empty();

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    return connection.writeLock(callback,
        lockTimeout: lockTimeout, debugContext: debugContext);
  }

  @override
  Future<T> withAllConnections<T>(
      Future<T> Function(
              SqliteWriteContext writer, List<SqliteReadContext> readers)
          block) {
    return writeLock((_) => block(connection, []));
  }
}
