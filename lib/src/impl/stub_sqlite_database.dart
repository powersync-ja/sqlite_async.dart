import 'package:sqlite_async/src/common/abstract_isolate_connection_factory.dart';
import 'package:sqlite_async/src/common/abstract_open_factory.dart';
import 'package:sqlite_async/src/common/abstract_sqlite_database.dart';
import 'package:sqlite_async/src/sqlite_connection.dart';
import 'package:sqlite_async/src/sqlite_options.dart';
import 'package:sqlite_async/src/update_notification.dart';

class SqliteDatabase extends AbstractSqliteDatabase {
  @override
  bool get closed => throw UnimplementedError();

  AbstractDefaultSqliteOpenFactory openFactory;

  @override
  int maxReaders;

  factory SqliteDatabase(
      {required path,
      int maxReaders = AbstractSqliteDatabase.defaultMaxReaders,
      SqliteOptions options = const SqliteOptions.defaults()}) {
    throw UnimplementedError();
  }

  SqliteDatabase.withFactory(this.openFactory,
      {this.maxReaders = AbstractSqliteDatabase.defaultMaxReaders}) {
    throw UnimplementedError();
  }

  @override
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
    // TODO: implement close
    throw UnimplementedError();
  }

  @override
  AbstractIsolateConnectionFactory isolateConnectionFactory() {
    // TODO: implement isolateConnectionFactory
    throw UnimplementedError();
  }
}
