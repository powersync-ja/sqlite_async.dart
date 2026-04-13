/// Custom requests used by this package to manage locks in shared workers.
@JS()
library;

import 'dart:js_interop';
import 'package:sqlite3_web/protocol_utils.dart' as proto;

enum CustomDatabaseMessageKind {
  ok,
  getAutoCommit,
  executeBatch,
  updateSubscriptionManagement,
  notifyUpdates,
}

extension type BaseCustomDatabaseMessage._raw(JSObject _) implements JSObject {
  external JSString get rawKind;

  external factory BaseCustomDatabaseMessage({required JSString rawKind});

  factory BaseCustomDatabaseMessage.getAutoCommit() {
    return BaseCustomDatabaseMessage(
      rawKind: CustomDatabaseMessageKind.getAutoCommit.name.toJS,
    );
  }

  factory BaseCustomDatabaseMessage.okResponse() {
    return BaseCustomDatabaseMessage(
      rawKind: CustomDatabaseMessageKind.ok.name.toJS,
    );
  }

  CustomDatabaseMessageKind get kind {
    return CustomDatabaseMessageKind.values.byName(rawKind.toDart);
  }
}

extension type CustomDatabaseMessage._raw(JSObject _)
    implements BaseCustomDatabaseMessage {
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

  external JSString get rawSql;

  external JSArray get rawParameters;

  /// Not set in earlier versions of this package.
  external JSArrayBuffer? get typeInfo;
}

extension type RunBatchRequest._raw(JSObject _)
    implements BaseCustomDatabaseMessage {
  external factory RunBatchRequest._({
    required JSString rawKind,
    required JSString rawSql,
    required JSArray<BatchParameters> parameters,
    required JSBoolean requireTransaction,
  });

  factory RunBatchRequest({
    required String sql,
    required List<List<Object?>> parameters,
    required bool requireTransaction,
  }) {
    return RunBatchRequest._(
      rawKind: CustomDatabaseMessageKind.executeBatch.name.toJS,
      rawSql: sql.toJS,
      parameters: parameters.map(BatchParameters.new).toList().toJS,
      requireTransaction: requireTransaction.toJS,
    );
  }

  external JSString get rawSql;
  external JSArray<BatchParameters> get parameters;
  external JSBoolean get requireTransaction;
}

extension type BatchParameters._raw(JSObject _) implements JSObject {
  external JSArray get parameters;
  external JSArrayBuffer get parameterTypes;

  external factory BatchParameters._({
    required JSArray parameters,
    required JSArrayBuffer parameterTypes,
  });

  factory BatchParameters(List<Object?> parameters) {
    final (params, types) = proto.serializeParameters(parameters);
    return BatchParameters._(parameters: params, parameterTypes: types);
  }

  List<Object?> get decodedParameters =>
      proto.deserializeParameters(parameters, parameterTypes);
}
