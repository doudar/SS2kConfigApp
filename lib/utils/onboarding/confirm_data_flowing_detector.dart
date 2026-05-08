import 'dart:async';

/// Detects 3 continuous seconds where both power>0 and cadence>0 are present.
///
/// The stability window resets when:
///   - power drops to 0 (onPowerUpdate(0))
///   - cadence drops to 0 (onCadenceUpdate(0))
///   - no new sample has arrived for >1s while the window was active
///
/// In tests, pass a [clock] function and call [tick] manually instead of
/// relying on the internal 200ms Timer.
class ConfirmDataFlowingDetector {
  final void Function() onStable;
  final DateTime Function() clock;

  int _lastPower = 0;
  int _lastCadence = 0;
  DateTime? _bothPresentAt;
  DateTime? _lastSampleAt;
  bool _fired = false;
  Timer? _timer;

  static const _window = Duration(seconds: 3);
  static const _silenceThreshold = Duration(seconds: 1);
  static const _pollInterval = Duration(milliseconds: 200);

  ConfirmDataFlowingDetector({
    required this.onStable,
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now()) {
    _timer = Timer.periodic(_pollInterval, (_) => tick());
  }

  void onPowerUpdate(int watts) {
    _lastPower = watts;
    _lastSampleAt = clock();
    if (watts == 0) _bothPresentAt = null;
    _evaluate();
  }

  void onCadenceUpdate(int cadence) {
    _lastCadence = cadence;
    _lastSampleAt = clock();
    if (cadence == 0) _bothPresentAt = null;
    _evaluate();
  }

  /// Called by the periodic timer, or directly in tests.
  /// Checks whether the silence threshold has been exceeded while an active
  /// window was running, and fires [onStable] when the 3s window completes.
  void tick() {
    if (_fired) return;
    final now = clock();

    // If we were in an active window and samples have gone silent, reset.
    if (_bothPresentAt != null &&
        _lastSampleAt != null &&
        now.difference(_lastSampleAt!) > _silenceThreshold) {
      _bothPresentAt = null;
      _lastSampleAt = null; // prevent immediate re-trigger until a new sample arrives
      return;
    }

    _evaluate();
  }

  void _evaluate() {
    if (_fired) return;
    final now = clock();

    if (_lastPower > 0 && _lastCadence > 0) {
      _bothPresentAt ??= now;
      if (now.difference(_bothPresentAt!) >= _window) {
        _fired = true;
        onStable();
      }
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
