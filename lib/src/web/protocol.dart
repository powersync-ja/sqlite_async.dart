/// Custom requests used by this package to manage locks in shared workers.
@JS()
library;

import 'dart:js_interop';

/// Custom function which exposes CommonDatabase.autocommit
const sqliteAsyncAutoCommitCommand = 'sqlite_async_autocommit';

enum CustomDatabaseMessageKind {
  requestSharedLock,
  requestExclusiveLock,
  releaseLock,
  lockObtained,
  getAutoCommit,
}

extension type CustomDatabaseMessage._raw(JSObject _) implements JSObject {
  external factory CustomDatabaseMessage._({
    required JSString rawKind,
  });

  factory CustomDatabaseMessage(CustomDatabaseMessageKind kind) {
    return CustomDatabaseMessage._(rawKind: kind.name.toJS);
  }

  external JSString get rawKind;

  CustomDatabaseMessageKind get kind {
    return CustomDatabaseMessageKind.values.byName(rawKind.toDart);
  }
}
