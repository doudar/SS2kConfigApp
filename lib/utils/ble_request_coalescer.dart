class CustomReadRequestCoalescer {
  final Map<String, Future<void>> _pendingRequests =
      <String, Future<void>>{};

  Future<void> schedule(
    List<int> packet,
    Future<void> Function(List<int> packet) operation,
  ) {
    final immutablePacket = List<int>.unmodifiable(packet);
    final isReadRequest =
        immutablePacket.isNotEmpty && immutablePacket.first == 0x01;
    if (!isReadRequest) {
      return operation(immutablePacket);
    }

    // Use every byte as the identity so indexed reads, such as power-table
    // rows, only coalesce when their indexes also match.
    final requestKey = immutablePacket.join(',');
    final existingRequest = _pendingRequests[requestKey];
    if (existingRequest != null) {
      return existingRequest;
    }

    final request = operation(immutablePacket);
    _pendingRequests[requestKey] = request;

    void removeCompletedRequest() {
      if (identical(_pendingRequests[requestKey], request)) {
        _pendingRequests.remove(requestKey);
      }
    }

    request.then<void>(
      (_) => removeCompletedRequest(),
      onError: (_) => removeCompletedRequest(),
    );
    return request;
  }

  void clear() {
    _pendingRequests.clear();
  }
}
