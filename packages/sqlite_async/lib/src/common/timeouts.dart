/// @docImport '../sqlite_connection.dart';
library;

import 'package:meta/meta.dart';

@internal
extension TimeoutDurationToFuture on Duration {
  /// Returns a future that completes with `void` after this duration.
  Future<void> get asTimeout => Future.delayed(this);
}

/// An exception thrown when calls to [SqliteConnection.readLock],
/// [SqliteConnection.writeLock] and similar methods are aborted or time out
/// before a connection could be obtained from the pool.
final class AbortException implements Exception {
  final String _methodName;

  AbortException(this._methodName);

  @override
  String toString() {
    return 'A call to $_methodName has been aborted';
  }
}
