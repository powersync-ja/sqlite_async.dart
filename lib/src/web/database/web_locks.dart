@JS()
library navigator_locks;

import 'package:js/js.dart';

@JS('navigator.locks')
external NavigatorLocks navigatorLocks;

abstract class NavigatorLocks {
  Future<T> request<T>(String name, Function callbacks);
  // Future<T> request<T>(String name, Future<T> Function(dynamic lock) callback);
}
