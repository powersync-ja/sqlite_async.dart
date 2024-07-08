import 'dart:isolate';

class SubscribeToUpdates {
  final SendPort port;

  SubscribeToUpdates(this.port);
}

class UnsubscribeToUpdates {
  final SendPort port;

  UnsubscribeToUpdates(this.port);
}
