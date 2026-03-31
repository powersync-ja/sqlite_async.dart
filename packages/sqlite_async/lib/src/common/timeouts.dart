extension TimeoutDurationToFuture on Duration {
  /// Returns a future that completes with `void` after this duration.
  Future<void> get asTimeout => Future.delayed(this);
}
