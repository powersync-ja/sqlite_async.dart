/// Custom requests used by this package to manage locks in shared workers.
@JS()
library;

import 'dart:js_interop';
import 'package:sqlite3_web/protocol_utils.dart' as proto;

enum CustomDatabaseMessageKind {
  requestSharedLock,
  requestExclusiveLock,
  releaseLock,
  lockObtained,
  getAutoCommit,
  executeInTransaction,
  executeBatchInTransaction,
  updateSubscriptionManagement,
  notifyUpdates,
}

extension type CustomDatabaseMessage._raw(JSObject _) implements JSObject {
  external factory CustomDatabaseMessage._({
    required JSString rawKind,
    JSString rawSql,
    JSArray rawParameters,
    JSArrayBuffer typeInfo,
  });

  factory CustomDatabaseMessage(CustomDatabaseMessageKind kind,
      [String? sql, List<Object?> parameters = const []]) {
    final rawSql = (sql ?? '').toJS;
    // Serializing parameters this way is backwards-compatible with dartify()
    // on the other end, but a bit more efficient while also suppporting sound
    // communcation between dart2js workers and dart2wasm clients.
    // Older workers ignore the typeInfo, but that's not a problem.
    final (rawParameters, typeInfo) = proto.serializeParameters(parameters);

    return CustomDatabaseMessage._(
      rawKind: kind.name.toJS,
      rawSql: rawSql,
      rawParameters: rawParameters,
      typeInfo: typeInfo,
    );
  }

  external JSString get rawKind;

  external JSString get rawSql;

  external JSArray get rawParameters;

  /// Not set in earlier versions of this package.
  external JSArrayBuffer? get typeInfo;

  CustomDatabaseMessageKind get kind {
    return CustomDatabaseMessageKind.values.byName(rawKind.toDart);
  }
}
