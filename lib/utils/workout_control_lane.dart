import 'dart:async';
import 'dart:typed_data';

import 'device_transport_state.dart';
import 'ftmsControlPoint.dart';

enum WorkoutControlKind { targetPower, simulationReset }

class WorkoutControlBatch {
  const WorkoutControlBatch({
    required this.kind,
    required this.watts,
    required this.commands,
    required this.generation,
    required this.epoch,
  });

  final WorkoutControlKind kind;
  final int? watts;
  final List<Uint8List> commands;
  final int generation;
  final int epoch;
}

typedef WorkoutBatchDispatcher =
    Future<bool> Function(WorkoutControlBatch batch, bool Function() isCurrent);
typedef WorkoutControlTimerFactory =
    Timer Function(Duration duration, void Function() callback);

class WorkoutControlLane {
  WorkoutControlLane({
    required DeviceTransportState Function() transportState,
    required bool Function() isReady,
    required WorkoutBatchDispatcher dispatch,
    WorkoutControlTimerFactory timerFactory = _defaultTimerFactory,
    this.retryDelay = const Duration(seconds: 1),
  }) : _transportState = transportState,
       _isReady = isReady,
       _dispatch = dispatch,
       _timerFactory = timerFactory;

  final DeviceTransportState Function() _transportState;
  final bool Function() _isReady;
  final WorkoutBatchDispatcher _dispatch;
  final WorkoutControlTimerFactory _timerFactory;
  final Duration retryDelay;

  _WorkoutControlDesired? _desired;
  _WorkoutControlRequest? _inFlight;
  _WorkoutControlRequest? _pending;
  _DeliveredWorkoutControl? _delivered;
  Timer? _retryTimer;
  int _generation = 0;
  bool _disposed = false;

  void setTargetPower(int watts, {bool force = false}) {
    // Ramp math runs inside the 100 ms workout tick, so an out-of-range target
    // from a malformed workout must not throw into the timer callback.
    watts = watts.clamp(0, 0x7fff);
    final targetCommand = FTMSControlPoint.targetPowerCommand(watts);
    final commands = <Uint8List>[targetCommand];
    if (watts == 0) {
      // Zero watts also returns the trainer to neutral simulation mode. Keep
      // both commands in one guarded batch so a newer ERG target can cancel
      // the mode switch before the second physical write.
      commands.add(
        FTMSControlPoint.indoorBikeSimulationCommand(
          windSpeed: 0,
          grade: 0,
          crr: 0,
          cw: 0,
        ),
      );
    }
    _request(
      _WorkoutControlDesired(
        kind: WorkoutControlKind.targetPower,
        watts: watts,
        commands: commands,
      ),
      force: force,
    );
  }

  void resetSimulation() {
    _request(
      _WorkoutControlDesired(
        kind: WorkoutControlKind.simulationReset,
        watts: null,
        commands: [
          FTMSControlPoint.indoorBikeSimulationCommand(
            windSpeed: 0,
            grade: 0,
            crr: 0,
            cw: 0,
          ),
        ],
      ),
      force: false,
    );
  }

  /// Drops the delivery record so the desired state is resent on the current
  /// epoch. Used when connection-scoped state is torn down and rebuilt without
  /// a phase change, where epoch-scoped deduplication would otherwise suppress
  /// a target the rebuilt session never received.
  void invalidateDelivery() {
    if (_disposed) return;
    _delivered = null;
    onAvailabilityChanged();
  }

  void onAvailabilityChanged() {
    if (_disposed) return;
    if (!_available) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _pending = null;
      return;
    }
    _drainPending();
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _desired = null;
    _inFlight = null;
    _pending = null;
  }

  bool get _available {
    final state = _transportState();
    return state.phase == DeviceTransportPhase.connected && _isReady();
  }

  void _request(_WorkoutControlDesired desired, {required bool force}) {
    if (_disposed) return;

    final epoch = _transportState().epoch;
    // `force` is deliberately absorbed here: an identical batch is already in
    // flight or pending for this epoch, so that delivery covers the request and
    // a second write would be redundant. Pinned by the lane test
    // 'force coalesces with identical request already in flight'.
    if (_hasMatchingActiveRequest(desired, epoch)) {
      _desired = desired;
      return;
    }

    _desired = desired;
    if (desired.kind == WorkoutControlKind.simulationReset &&
        _delivered?.desired.kind == WorkoutControlKind.targetPower) {
      _delivered = null;
    }

    if (!force && _isDelivered(desired, epoch)) return;

    _generation++;
    if (!_available) {
      _pending = null;
      return;
    }

    final request = _WorkoutControlRequest(
      desired: desired,
      generation: _generation,
      epoch: epoch,
    );
    if (_retryTimer != null || _inFlight != null) {
      _pending = request;
      return;
    }
    _start(request);
  }

  void _scheduleDesired({required bool force}) {
    if (_disposed) return;
    final desired = _desired;
    if (desired == null || !_available) return;
    final epoch = _transportState().epoch;
    if (_hasMatchingActiveRequest(desired, epoch)) {
      return;
    }
    if (!force && _isDelivered(desired, epoch)) return;

    _generation++;
    final request = _WorkoutControlRequest(
      desired: desired,
      generation: _generation,
      epoch: epoch,
    );
    if (_retryTimer != null || _inFlight != null) {
      _pending = request;
    } else {
      _start(request);
    }
  }

  void _start(_WorkoutControlRequest request) {
    _inFlight = request;
    final batch = WorkoutControlBatch(
      kind: request.desired.kind,
      watts: request.desired.watts,
      commands: request.desired.commands,
      generation: request.generation,
      epoch: request.epoch,
    );
    _run(request, batch);
  }

  Future<void> _run(
    _WorkoutControlRequest request,
    WorkoutControlBatch batch,
  ) async {
    var succeeded = false;
    Object? failure;
    try {
      succeeded = await _dispatch(batch, () => _isCurrent(request));
    } catch (error) {
      failure = error;
    }

    if (identical(_inFlight, request)) _inFlight = null;

    if (!_isCurrent(request)) {
      _drainPending();
      return;
    }

    if (failure != null) {
      _armRetry();
      return;
    }

    if (succeeded) {
      _delivered = _DeliveredWorkoutControl(
        desired: request.desired,
        epoch: request.epoch,
      );
    }
    _drainPending();
  }

  bool _isCurrent(_WorkoutControlRequest request) {
    final state = _transportState();
    return !_disposed &&
        request.generation == _generation &&
        request.epoch == state.epoch &&
        state.phase == DeviceTransportPhase.connected &&
        _isReady();
  }

  bool _isDelivered(_WorkoutControlDesired desired, int epoch) {
    final delivered = _delivered;
    return delivered != null &&
        delivered.epoch == epoch &&
        delivered.desired.samePayload(desired);
  }

  bool _hasMatchingActiveRequest(_WorkoutControlDesired desired, int epoch) {
    final inFlight = _inFlight;
    if (inFlight != null &&
        inFlight.epoch == epoch &&
        inFlight.desired.samePayload(desired)) {
      return true;
    }
    final pending = _pending;
    return pending != null &&
        pending.epoch == epoch &&
        pending.desired.samePayload(desired);
  }

  void _armRetry() {
    if (!_available || _retryTimer != null) return;
    _retryTimer = _timerFactory(retryDelay, () {
      _retryTimer = null;
      if (!_available) return;
      _pending = null;
      _scheduleDesired(force: true);
    });
  }

  void _drainPending() {
    if (_disposed) return;
    if (_inFlight != null || _retryTimer != null || !_available) return;
    final pending = _pending;
    _pending = null;
    if (pending != null && _isCurrent(pending)) {
      _start(pending);
      return;
    }
    _scheduleDesired(force: false);
  }

  static Timer _defaultTimerFactory(
    Duration duration,
    void Function() callback,
  ) => Timer(duration, callback);
}

class _WorkoutControlDesired {
  const _WorkoutControlDesired({
    required this.kind,
    required this.watts,
    required this.commands,
  });

  final WorkoutControlKind kind;
  final int? watts;
  final List<Uint8List> commands;

  bool samePayload(_WorkoutControlDesired other) {
    if (kind != other.kind || watts != other.watts) return false;
    if (commands.length != other.commands.length) return false;
    for (var index = 0; index < commands.length; index++) {
      final left = commands[index];
      final right = other.commands[index];
      if (left.length != right.length) return false;
      for (var byte = 0; byte < left.length; byte++) {
        if (left[byte] != right[byte]) return false;
      }
    }
    return true;
  }
}

class _WorkoutControlRequest {
  const _WorkoutControlRequest({
    required this.desired,
    required this.generation,
    required this.epoch,
  });

  final _WorkoutControlDesired desired;
  final int generation;
  final int epoch;
}

class _DeliveredWorkoutControl {
  const _DeliveredWorkoutControl({required this.desired, required this.epoch});

  final _WorkoutControlDesired desired;
  final int epoch;
}
