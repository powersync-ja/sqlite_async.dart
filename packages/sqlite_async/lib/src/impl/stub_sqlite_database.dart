import 'package:meta/meta.dart';
import 'package:sqlite_async/src/common/isolate_connection_factory.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/common/sqlite_database.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_options.dart';
import 'package:sqlite_async/src/sqlite_queries.dart';
import 'package:sqlite_async/src/update_notification.dart';

class SqliteDatabaseImpl
    with SqliteQueries, SqliteDatabaseMixin
    implements SqliteDatabase {
  @override
  bool get closed => throw UnimplementedError();

  @override
  AbstractDefaultSqliteOpenFactory openFactory;

  @override
  int maxReaders;

  factory SqliteDatabaseImpl(
      {required String path,
      int maxReaders = SqliteDatabase.defaultMaxReaders,
      SqliteOptions options = const SqliteOptions.defaults()}) {
    throw UnimplementedError();
  }

  SqliteDatabaseImpl.withFactory(this.openFactory,
      {this.maxReaders = SqliteDatabase.defaultMaxReaders}) {
    throw UnimplementedError();
  }

  @override
  @protected
  Future<void> get isInitialized => throw UnimplementedError();

  @override
  Stream<UpdateNotification> get updates => throw UnimplementedError();

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
    throw UnimplementedError();
  }

  @override
  IsolateConnectionFactory isolateConnectionFactory() {
    throw UnimplementedError();
  }

  @override
  Future<bool> getAutoCommit() {
    throw UnimplementedError();
  }

  @override
  Future<T> withAllConnections<T>(
      Future<T> Function(
              SqliteWriteContext writer, List<SqliteReadContext> readers)
          block) {
    throw UnimplementedError();
  }
}
