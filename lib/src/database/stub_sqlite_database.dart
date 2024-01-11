import 'package:sqlite_async/sqlite_async.dart';

class SqliteDatabase extends AbstractSqliteDatabase {
  @override
  bool get closed => throw UnimplementedError();

  factory SqliteDatabase(
      {required path,
      int maxReaders = AbstractSqliteDatabase.defaultMaxReaders,
      SqliteOptions options = const SqliteOptions.defaults()}) {
    throw UnimplementedError();
  }

  SqliteDatabase.withFactory(SqliteOpenFactory openFactory,
      {int maxReaders = AbstractSqliteDatabase.defaultMaxReaders}) {
    throw UnimplementedError();
  }

  @override
  Future<T> readLock<T>(Future<T> Function(SqliteReadContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    throw UnimplementedError();
  }

  @override
  Future<T> writeLock<T>(Future<T> Function(SqliteWriteContext tx) callback,
      {Duration? lockTimeout, String? debugContext}) {
    throw UnimplementedError();
  }

  @override
  Future<void> close() {
    // TODO: implement close
    throw UnimplementedError();
  }

  @override
  IsolateConnectionFactory isolateConnectionFactory() {
    // TODO: implement isolateConnectionFactory
    throw UnimplementedError();
  }
}
