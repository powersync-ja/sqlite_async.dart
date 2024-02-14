@JS()
library navigator_locks;

import 'package:js/js.dart';

@JS('navigator.locks')
external NavigatorLocks navigatorLocks;

/// TODO Web navigator lock interface should be used to support multiple tabs
abstract class NavigatorLocks {
  Future<T> request<T>(String name, Function callbacks);
}
