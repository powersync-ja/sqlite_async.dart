extension TimeoutDurationToFuture on Duration {
  Future<void> get asTimeout => Future.delayed(this);
}
