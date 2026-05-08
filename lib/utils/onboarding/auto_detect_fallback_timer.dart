import 'dart:async';

class AutoDetectFallbackTimer {
  final void Function() onTimeout;
  final DateTime Function() clock;

  static const _duration = Duration(seconds: 30);
  static const _pollInterval = Duration(milliseconds: 200);

  DateTime? _startedAt;
  bool _cancelled = false;
  bool _fired = false;
  Timer? _timer;

  AutoDetectFallbackTimer({
    required this.onTimeout,
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now()) {
    _startedAt = (clock ?? (() => DateTime.now()))();
    _timer = Timer.periodic(_pollInterval, (_) => tick());
  }

  void tick() {
    if (_cancelled || _fired || _startedAt == null) return;
    if (clock().difference(_startedAt!) >= _duration) {
      _fired = true;
      onTimeout();
    }
  }

  void restart() {
    _fired = false;
    _startedAt = clock();
  }

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
  }
}
