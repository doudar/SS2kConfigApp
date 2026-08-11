class ConnectionSetupCoordinator {
  Future<void>? _inFlight;
  int _generation = 0;

  Future<void>? get inFlight => _inFlight;

  bool isCurrent(int generation) => generation == _generation;

  Future<void> run(Future<void> Function(int generation) action) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    late final Future<void> future;
    future = Future.sync(() => action(_generation)).whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    _inFlight = future;
    return future;
  }

  void invalidate() {
    _generation++;
    _inFlight = null;
  }
}
