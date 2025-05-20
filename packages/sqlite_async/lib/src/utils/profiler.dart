import 'dart:developer';

extension TimeSync on TimelineTask? {
  T timeSync<T>(String name, TimelineSyncFunction<T> function,
      {String? sql, List<Object?>? parameters}) {
    final currentTask = this;
    if (currentTask == null) {
      return function();
    }

    final (resolvedName, args) =
        profilerNameAndArgs(name, sql: sql, parameters: parameters);
    currentTask.start(resolvedName, arguments: args);

    try {
      return function();
    } finally {
      currentTask.finish();
    }
  }

  Future<T> timeAsync<T>(String name, TimelineSyncFunction<Future<T>> function,
      {String? sql, List<Object?>? parameters}) {
    final currentTask = this;
    if (currentTask == null) {
      return function();
    }

    final (resolvedName, args) =
        profilerNameAndArgs(name, sql: sql, parameters: parameters);
    currentTask.start(resolvedName, arguments: args);

    return Future.sync(function).whenComplete(() {
      currentTask.finish();
    });
  }
}

(String, Map) profilerNameAndArgs(String name,
    {String? sql, List<Object?>? parameters}) {
  // On native platforms, we want static names for tasks because every
  // unique key here shows up in a separate line in Perfetto: https://github.com/dart-lang/sdk/issues/56274
  // On the web however, the names are embedded in the timeline slices and
  // it's convenient to include the SQL there.
  const isWeb = bool.fromEnvironment('dart.library.js_interop');
  var resolvedName = '$profilerPrefix$name';
  if (isWeb && sql != null) {
    resolvedName = ' $sql';
  }

  return (
    resolvedName,
    {
      if (sql != null) 'sql': sql,
      if (parameters != null)
        'parameters': [
          for (final parameter in parameters)
            if (parameter is List) '<blob>' else parameter
        ],
    }
  );
}

const profilerPrefix = 'sqlite_async:';
