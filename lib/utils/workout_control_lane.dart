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
    this.keepAliveInterval = const Duration(seconds: 2),
  }) : _transportState = transportState,
       _isReady = isReady,
       _dispatch = dispatch,
       _timerFactory = timerFactory;

  final DeviceTransportState Function() _transportState;
  final bool Function() _isReady;
  final WorkoutBatchDispatcher _dispatch;
  final WorkoutControlTimerFactory _timerFactory;
  final Duration retryDelay;

  /// How long an unchanged ERG target may go unwritten before it is re-sent.
  ///
  /// The firmware uses the last control point opcode as its operating mode, and
  /// `ErgMode::_userIsSpinning` rewrites that mode to
  /// SetIndoorBikeSimulationParameters whenever cadence sits at or below
  /// MIN_ERG_CADENCE (30 rpm). Nothing on the device restores it; only another
  /// Set Target Power write re-arms ERG. Every spin-up from a standstill passes
  /// through 1-29 rpm, so a target delivered once at the top of a steady
  /// segment is discarded and that segment never applies resistance. Zwift and
  /// TrainerRoad both re-assert continuously, which is why they never see this.
  /// Re-asserting is also the only fix that works on already-shipped firmware.
  final Duration keepAliveInterval;

  _WorkoutControlDesired? _desired;
  _WorkoutControlRequest? _inFlight;
  _WorkoutControlRequest? _pending;
  _DeliveredWorkoutControl? _delivered;
  Timer? _retryTimer;
  Timer? _keepAliveTimer;
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
      _syncKeepAlive();
      return;
    }
    _drainPending();
    _syncKeepAlive();
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
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
    _requestInner(desired, force: force);
    // Every early return in `_requestInner` still leaves `_desired` updated, so
    // the keep-alive is re-evaluated here rather than on the paths that happen
    // to dispatch. The deduped steady-state tick is exactly the path that
    // returns early and exactly the one that needs the keep-alive running.
    _syncKeepAlive();
  }

  void _requestInner(_WorkoutControlDesired desired, {required bool force}) {
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
      // The target was just written, so the silence window starts over. Without
      // this a keep-alive armed before a real target change would fire almost
      // immediately after it and write the same value twice.
      _keepAliveTimer?.cancel();
      _keepAliveTimer = null;
    }
    _drainPending();
    _syncKeepAlive();
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

  /// True while the desired state is an ERG hold that the firmware can silently
  /// drop. Zero-watt targets are excluded: their batch ends with a simulation
  /// command, so the trainer is meant to be out of ERG and re-asserting would
  /// just re-run the mode switch every interval. Simulation resets are excluded
  /// for the same reason, which is also what stops the keep-alive on pause and
  /// stop, since both route through `resetSimulation`.
  bool get _keepAliveApplies {
    final desired = _desired;
    return desired != null &&
        desired.kind == WorkoutControlKind.targetPower &&
        (desired.watts ?? 0) > 0 &&
        _available;
  }

  void _syncKeepAlive() {
    if (_disposed || !_keepAliveApplies) {
      _keepAliveTimer?.cancel();
      _keepAliveTimer = null;
      return;
    }
    if (_keepAliveTimer != null || keepAliveInterval <= Duration.zero) return;
    _keepAliveTimer = _timerFactory(keepAliveInterval, () {
      _keepAliveTimer = null;
      if (!_keepAliveApplies) return;
      // A retry already re-sends the desired state with force, so stay out of
      // its way rather than stacking a second write behind it.
      if (_retryTimer == null) _scheduleDesired(force: true);
      _syncKeepAlive();
    });
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
