/// Custom requests used by this package to manage locks in shared workers.
@JS()
library;

import 'dart:js_interop';

enum CustomDatabaseMessageKind {
  requestSharedLock,
  requestExclusiveLock,
  releaseLock,
  lockObtained,
  getAutoCommit,
  executeInTransaction,
  executeBatchInTransaction,
}

extension type CustomDatabaseMessage._raw(JSObject _) implements JSObject {
  external factory CustomDatabaseMessage._({
    required JSString rawKind,
    JSString rawSql,
    JSArray rawParameters,
  });

  factory CustomDatabaseMessage(CustomDatabaseMessageKind kind,
      [String? sql, List<Object?> parameters = const []]) {
    final rawSql = sql?.toJS ?? ''.toJS;
    final rawParameters =
        <JSAny?>[for (final parameter in parameters) parameter.jsify()].toJS;
    return CustomDatabaseMessage._(
        rawKind: kind.name.toJS, rawSql: rawSql, rawParameters: rawParameters);
  }

  external JSString get rawKind;

  external JSString get rawSql;

  external JSArray get rawParameters;

  CustomDatabaseMessageKind get kind {
    return CustomDatabaseMessageKind.values.byName(rawKind.toDart);
  }
}
