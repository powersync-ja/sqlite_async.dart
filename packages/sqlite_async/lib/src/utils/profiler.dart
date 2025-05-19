import 'dart:developer';

/// Turns the [parameters] for an SQL query into a [Map] that can be serialized
/// to JSON (as a requirement for using it as a timeline argument).
Map parameterArgs(List<Object?> parameters) {
  return {
    'parameters': [
      for (final parameter in parameters)
        if (parameter is List) '<blob>' else parameter
    ],
  };
}

Map timelineArgs(String sql, List<Object?> parameters) {
  return parameterArgs(parameters)..['sql'] = sql;
}

extension TimeSync on TimelineTask? {
  T timeSync<T>(String name, TimelineSyncFunction<T> function,
      {Map? arguments}) {
    final currentTask = this;
    if (currentTask == null) {
      return function();
    }

    try {
      currentTask.start(name, arguments: arguments);
      return function();
    } finally {
      currentTask.finish();
    }
  }
}
