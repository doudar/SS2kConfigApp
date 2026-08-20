import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/device_transport_state.dart';
import 'package:ss2kconfigapp/utils/workout_control_lane.dart';

void main() {
  test('steady target dedupes while force redelivers after success', () async {
    final harness = _Harness();
    final lane = harness.createLane();

    lane.setTargetPower(250);
    await _flush();
    lane.setTargetPower(250);
    await _flush();
    expect(harness.writes, hasLength(1));

    lane.setTargetPower(250, force: true);
    await _flush();
    expect(harness.writes, hasLength(2));
  });

  test('force coalesces with identical request already in flight', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final harness = _Harness(
      beforeWrite: () {
        if (!started.isCompleted) started.complete();
        return gate.future;
      },
    );
    final lane = harness.createLane();

    lane.setTargetPower(200);
    await started.future;
    lane.setTargetPower(200, force: true);
    gate.complete();
    await _flush();

    expect(harness.writes, [
      [0x05, 0xc8, 0x00],
    ]);
  });

  test('rapid requests retain only the newest pending target', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final harness = _Harness(
      beforeWrite: () {
        if (!started.isCompleted) started.complete();
        return gate.future;
      },
    );
    final lane = harness.createLane();

    lane.setTargetPower(100);
    await started.future;
    lane.setTargetPower(200);
    lane.setTargetPower(300);
    gate.complete();
    await _flush(4);

    expect(harness.writes, [
      [0x05, 0x2c, 0x01],
    ]);
  });

  test('superseding zero target skips its simulation command', () async {
    final firstWrite = Completer<void>();
    final continueBatch = Completer<void>();
    final harness = _Harness(
      afterWrite: (index) async {
        if (index == 0 && !firstWrite.isCompleted) {
          firstWrite.complete();
          await continueBatch.future;
        }
      },
    );
    final lane = harness.createLane();

    lane.setTargetPower(0);
    await firstWrite.future;
    lane.setTargetPower(250);
    continueBatch.complete();
    await _flush(4);

    expect(harness.writes, [
      [0x05, 0x00, 0x00],
      [0x05, 0xfa, 0x00],
    ]);
  });

  test('one retry timer keeps only the newest payload', () async {
    final timers = <_ManualTimer>[];
    var failures = 1;
    final harness = _Harness(
      fail: () {
        if (failures == 0) return false;
        failures--;
        return true;
      },
    );
    final lane = harness.createLane(
      timerFactory: (duration, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    lane.setTargetPower(100);
    await _flush();
    expect(timers, hasLength(1));

    lane.setTargetPower(200);
    lane.setTargetPower(300);
    expect(timers, hasLength(1));
    timers.single.fire();
    await _flush(4);

    expect(harness.writes, [
      [0x05, 0x2c, 0x01],
    ]);
  });

  test('failure from a superseded request does not arm retry', () async {
    final failure = Completer<void>();
    final started = Completer<void>();
    final timers = <_ManualTimer>[];
    var dispatchCount = 0;
    final harness = _Harness(
      beforeWrite: () async {
        dispatchCount++;
        if (dispatchCount == 1) {
          started.complete();
          await failure.future;
          throw StateError('stale transport failure');
        }
      },
    );
    final lane = harness.createLane(
      timerFactory: (duration, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    lane.setTargetPower(100);
    await started.future;
    lane.setTargetPower(200);
    failure.complete();
    await _flush(4);

    expect(timers, isEmpty);
    expect(harness.writes, [
      [0x05, 0xc8, 0x00],
    ]);
  });

  test('disconnect retains desired target and reconnect drains once', () async {
    final timers = <_ManualTimer>[];
    final harness = _Harness();
    final lane = harness.createLane(
      timerFactory: (duration, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );

    harness.ready = false;
    harness.state = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.reconnecting,
      epoch: 1,
    );
    lane.onAvailabilityChanged();
    lane.setTargetPower(220);
    lane.setTargetPower(230);

    harness.ready = true;
    harness.state = const DeviceTransportState(
      transport: DeviceTransportKind.bluetooth,
      phase: DeviceTransportPhase.connected,
      epoch: 2,
    );
    lane.onAvailabilityChanged();
    await _flush();

    expect(harness.writes, [
      [0x05, 0xe6, 0x00],
    ]);
    expect(timers, isEmpty);
  });

  test(
    'reconnect auto-drain and immediate force send latest target once',
    () async {
      final harness = _Harness()
        ..ready = false
        ..state = const DeviceTransportState(
          transport: DeviceTransportKind.bluetooth,
          phase: DeviceTransportPhase.reconnecting,
          epoch: 1,
        );
      final lane = harness.createLane();
      lane.onAvailabilityChanged();
      lane.setTargetPower(200);
      lane.setTargetPower(250);

      harness
        ..ready = true
        ..state = const DeviceTransportState(
          transport: DeviceTransportKind.bluetooth,
          phase: DeviceTransportPhase.connected,
          epoch: 2,
        );
      lane.onAvailabilityChanged();
      lane.setTargetPower(250, force: true);
      await _flush(4);

      expect(harness.writes, [
        [0x05, 0xfa, 0x00],
      ]);
    },
  );

  test(
    'pending request drains when readiness returns in the same epoch',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      var dispatchCount = 0;
      final harness = _Harness(
        beforeWrite: () async {
          dispatchCount++;
          if (dispatchCount == 1) {
            started.complete();
            await gate.future;
            throw StateError('readiness lost');
          }
        },
      );
      final lane = harness.createLane();

      lane.setTargetPower(100);
      await started.future;
      lane.setTargetPower(200);
      harness.ready = false;
      gate.complete();
      await _flush(4);

      harness.ready = true;
      lane.onAvailabilityChanged();
      await _flush(4);

      expect(harness.writes, [
        [0x05, 0xc8, 0x00],
      ]);
    },
  );

  test('in-flight completion after dispose does not redispatch', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    var dispatchCount = 0;
    final harness = _Harness(
      beforeWrite: () async {
        dispatchCount++;
        started.complete();
        await gate.future;
      },
    );
    final lane = harness.createLane();

    lane.setTargetPower(200);
    await started.future;
    lane.dispose();
    gate.complete();
    await _flush(6);

    expect(dispatchCount, 1);
    expect(harness.writes, isEmpty);
  });

  test('connected but not ready waits for FTMS availability', () async {
    final harness = _Harness()..ready = false;
    final lane = harness.createLane();

    lane.setTargetPower(180);
    await _flush();
    expect(harness.writes, isEmpty);

    harness.ready = true;
    lane.onAvailabilityChanged();
    await _flush();
    expect(harness.writes, [
      [0x05, 0xb4, 0x00],
    ]);
  });

  test('negative targets clamp to the zero-target batch', () async {
    final harness = _Harness();
    final lane = harness.createLane();

    lane.setTargetPower(-50);
    await _flush(4);

    expect(harness.writes, [
      [0x05, 0x00, 0x00],
      [0x11, 0, 0, 0, 0, 0, 0],
    ]);
  });

  test('epoch bump while connected redelivers the same target once', () async {
    final harness = _Harness();
    final lane = harness.createLane();

    lane.setTargetPower(240);
    await _flush();
    lane.setTargetPower(240);
    await _flush();
    expect(harness.writes, hasLength(1));

    harness.state = const DeviceTransportState(
      transport: DeviceTransportKind.dircon,
      phase: DeviceTransportPhase.connected,
      epoch: 2,
    );
    lane.onAvailabilityChanged();
    await _flush(4);
    lane.setTargetPower(240);
    await _flush(4);

    expect(harness.writes, [
      [0x05, 0xf0, 0x00],
      [0x05, 0xf0, 0x00],
    ]);
  });

  test('invalidateDelivery resends the target within the same epoch', () async {
    final harness = _Harness();
    final lane = harness.createLane();

    lane.setTargetPower(210);
    await _flush();
    expect(harness.writes, hasLength(1));

    lane.invalidateDelivery();
    await _flush(4);

    expect(harness.writes, [
      [0x05, 0xd2, 0x00],
      [0x05, 0xd2, 0x00],
    ]);
  });

  test(
    'simulation reset supersedes target and repeated reset dedupes',
    () async {
      final harness = _Harness();
      final lane = harness.createLane();

      lane.setTargetPower(200);
      await _flush();
      lane.resetSimulation();
      await _flush();
      lane.resetSimulation();
      await _flush();

      expect(harness.writes, [
        [0x05, 0xc8, 0x00],
        [0x11, 0, 0, 0, 0, 0, 0],
      ]);
    },
  );
}

class _Harness {
  _Harness({this.beforeWrite, this.afterWrite, this.fail});

  DeviceTransportState state = const DeviceTransportState(
    transport: DeviceTransportKind.bluetooth,
    phase: DeviceTransportPhase.connected,
    epoch: 1,
  );
  bool ready = true;
  final Future<void> Function()? beforeWrite;
  final Future<void> Function(int index)? afterWrite;
  final bool Function()? fail;
  final List<List<int>> writes = [];

  WorkoutControlLane createLane({WorkoutControlTimerFactory? timerFactory}) {
    return WorkoutControlLane(
      transportState: () => state,
      isReady: () => ready,
      timerFactory:
          timerFactory ?? (duration, callback) => Timer(duration, callback),
      dispatch: (batch, isCurrent) async {
        await beforeWrite?.call();
        if (fail?.call() ?? false) throw StateError('write failed');
        for (var index = 0; index < batch.commands.length; index++) {
          if (!isCurrent()) return false;
          writes.add(List<int>.from(batch.commands[index]));
          await afterWrite?.call(index);
        }
        return isCurrent();
      },
    );
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this._callback);

  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}

Future<void> _flush([int turns = 2]) async {
  for (var turn = 0; turn < turns; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}
