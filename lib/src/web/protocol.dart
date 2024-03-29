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
}

extension type CustomDatabaseMessage._(JSObject _) implements JSObject {
  external factory CustomDatabaseMessage({
    required JSString rawKind,
  });

  external JSString get rawKind;

  CustomDatabaseMessageKind get kind {
    return CustomDatabaseMessageKind.values.byName(rawKind.toDart);
  }
}
