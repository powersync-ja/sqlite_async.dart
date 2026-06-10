import 'package:sqlite3_web/sqlite3_web.dart';

import '../sqlite_options.dart';

/// A ref-counted [WebSqlite] wrapper.
///
/// Each reference is represented as [FinalizableWebSqliteResource], which have
/// a finalizer attached to them. When all resources pointing to this instance
/// are finalized, we can close the inner [WebSqlite] instance.
final class _RefCountedWebSqlite {
  final Future<WebSqlite> instance;
  int _users = 0;

  _RefCountedWebSqlite._(this.instance);

  static (_RefCountedWebSqlite, FinalizableWebSqliteResource) create(
      Future<WebSqlite> instance) {
    final ref = _RefCountedWebSqlite._(instance);
    ref._users = 1;
    return (ref, FinalizableWebSqliteResource._(ref));
  }

  FinalizableWebSqliteResource reference() {
    assert(_users > 0);
    _users++;
    return FinalizableWebSqliteResource._(this);
  }

  void decrementUsers() {
    _users--;
    if (_users == 0) {
      instance.then((sqlite) => sqlite.close());
    }
  }
}

final class FinalizableWebSqliteResource {
  final _RefCountedWebSqlite _instance;
  var _closed = false;

  FinalizableWebSqliteResource._(this._instance) {
    _finalizer.attach(this, _instance, detach: this);
  }

  Future<WebSqlite> get sqlite => _instance.instance;

  void close() {
    if (!_closed) {
      _closed = true;
      _instance.decrementUsers();
      _finalizer.detach(this);
    }
  }

  FinalizableWebSqliteResource clone() =>
      FinalizableWebSqliteResource._(_instance);

  static final Finalizer<_RefCountedWebSqlite> _finalizer =
      Finalizer((r) => r.decrementUsers());
}

/// Active [WebSqlite] instance, keyed by options.
final Map<String, _RefCountedWebSqlite> _activeSqliteInstances = {};

FinalizableWebSqliteResource resolveWebSqliteResource(
    WebSqliteOptions options, Future<WebSqlite> Function() open) {
  final cacheKey = options.wasmUri + options.workerUri;

  if (_activeSqliteInstances[cacheKey] case final instance?
      when instance._users > 0) {
    return instance.reference();
  }

  final (sqlite, ref) = _RefCountedWebSqlite.create(open());
  _activeSqliteInstances[cacheKey] = sqlite;
  return ref;
}
