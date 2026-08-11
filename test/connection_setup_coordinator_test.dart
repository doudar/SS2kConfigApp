import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/connection_setup_coordinator.dart';

void main() {
  group('ConnectionSetupCoordinator', () {
    test('shares one setup operation between concurrent callers', () async {
      final coordinator = ConnectionSetupCoordinator();
      final releaseSetup = Completer<void>();
      var calls = 0;

      Future<void> setup(int _) async {
        calls++;
        await releaseSetup.future;
      }

      final first = coordinator.run(setup);
      final second = coordinator.run(setup);

      expect(identical(first, second), isTrue);
      expect(calls, 1);

      releaseSetup.complete();
      await Future.wait([first, second]);
    });

    test('allows a new setup after the previous operation completes', () async {
      final coordinator = ConnectionSetupCoordinator();
      var calls = 0;

      await coordinator.run((_) async => calls++);
      await coordinator.run((_) async => calls++);

      expect(calls, 2);
    });

    test(
      'invalidation permits reconnect setup and marks old work stale',
      () async {
        final coordinator = ConnectionSetupCoordinator();
        final releaseOldSetup = Completer<void>();
        var oldGeneration = -1;
        var newCalls = 0;

        final oldSetup = coordinator.run((generation) async {
          oldGeneration = generation;
          await releaseOldSetup.future;
        });

        coordinator.invalidate();
        expect(coordinator.isCurrent(oldGeneration), isFalse);

        final newSetup = coordinator.run((generation) async {
          newCalls++;
          expect(coordinator.isCurrent(generation), isTrue);
        });
        await newSetup;

        releaseOldSetup.complete();
        await oldSetup;

        await coordinator.run((_) async => newCalls++);
        expect(newCalls, 2);
      },
    );
  });
}
