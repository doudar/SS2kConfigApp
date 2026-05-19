import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/onboarding/wizard_step_machine.dart';

void main() {
  late WizardStepMachine machine;

  setUp(() {
    machine = WizardStepMachine();
  });

  group('activeSteps', () {
    test('null bikeType returns [welcome, bikeType]', () {
      expect(machine.activeSteps(bikeType: null), [
        WizardStepId.welcome,
        WizardStepId.bikeType,
      ]);
    });

    test('mostSpinBikes does not include sideSwitch', () {
      final steps = machine.activeSteps(bikeType: BikeType.mostSpinBikes);
      expect(steps.contains(WizardStepId.sideSwitch), isFalse);
      expect(steps.first, WizardStepId.welcome);
      expect(steps.last, WizardStepId.completion);
    });

    test('pelotonBikePlus does not include sideSwitch', () {
      final steps = machine.activeSteps(bikeType: BikeType.pelotonBikePlus);
      expect(steps.contains(WizardStepId.sideSwitch), isFalse);
      expect(steps.first, WizardStepId.welcome);
      expect(steps.last, WizardStepId.completion);
    });

    test('pelotonOriginal includes sensorWiring then sideSwitch after wiring', () {
      final steps = machine.activeSteps(bikeType: BikeType.pelotonOriginal);
      expect(steps.contains(WizardStepId.sideSwitch), isTrue);
      expect(steps.contains(WizardStepId.sensorWiring), isTrue);
      final wiringIndex = steps.indexOf(WizardStepId.wiring);
      final sensorWiringIndex = steps.indexOf(WizardStepId.sensorWiring);
      final sideSwitchIndex = steps.indexOf(WizardStepId.sideSwitch);
      expect(sensorWiringIndex, wiringIndex + 1);
      expect(sideSwitchIndex, sensorWiringIndex + 1);
      expect(steps.first, WizardStepId.welcome);
      expect(steps.last, WizardStepId.completion);
    });

    test('mostSpinBikes full step list matches contract', () {
      expect(machine.activeSteps(bikeType: BikeType.mostSpinBikes), [
        WizardStepId.welcome,
        WizardStepId.bikeType,
        WizardStepId.hardwareInstall,
        WizardStepId.wiring,
        WizardStepId.ss2kConnection,
        WizardStepId.dataSource,
        WizardStepId.bikeDataTest,
        WizardStepId.motorTest,
        WizardStepId.physicalShifter,
        WizardStepId.hrm,
        WizardStepId.wifi,
        WizardStepId.completion,
      ]);
    });

    test('pelotonOriginal full step list matches contract', () {
      expect(machine.activeSteps(bikeType: BikeType.pelotonOriginal), [
        WizardStepId.welcome,
        WizardStepId.bikeType,
        WizardStepId.hardwareInstall,
        WizardStepId.wiring,
        WizardStepId.sensorWiring,
        WizardStepId.sideSwitch,
        WizardStepId.ss2kConnection,
        WizardStepId.dataSource,
        WizardStepId.bikeDataTest,
        WizardStepId.motorTest,
        WizardStepId.physicalShifter,
        WizardStepId.hrm,
        WizardStepId.wifi,
        WizardStepId.completion,
      ]);
    });
  });

  group('nextStep', () {
    test('throws when advancing from bikeType without selection', () {
      final session = WizardSessionSnapshot(bikeType: null);
      expect(
        () => machine.nextStep(
          currentStep: WizardStepId.bikeType,
          session: session,
        ),
        throwsStateError,
      );
    });

    test('happy path end-to-end for mostSpinBikes', () {
      final session = WizardSessionSnapshot(bikeType: BikeType.mostSpinBikes);
      final steps = machine.activeSteps(bikeType: BikeType.mostSpinBikes);
      for (int i = 0; i < steps.length - 1; i++) {
        final next = machine.nextStep(currentStep: steps[i], session: session);
        expect(next, steps[i + 1], reason: 'from ${steps[i]} expected ${steps[i + 1]}');
      }
    });

    test('happy path end-to-end for pelotonBikePlus', () {
      final session = WizardSessionSnapshot(bikeType: BikeType.pelotonBikePlus);
      final steps = machine.activeSteps(bikeType: BikeType.pelotonBikePlus);
      for (int i = 0; i < steps.length - 1; i++) {
        final next = machine.nextStep(currentStep: steps[i], session: session);
        expect(next, steps[i + 1]);
      }
    });

    test('happy path end-to-end for pelotonOriginal', () {
      final session = WizardSessionSnapshot(bikeType: BikeType.pelotonOriginal);
      final steps = machine.activeSteps(bikeType: BikeType.pelotonOriginal);
      for (int i = 0; i < steps.length - 1; i++) {
        final next = machine.nextStep(currentStep: steps[i], session: session);
        expect(next, steps[i + 1]);
      }
    });

    test('nextStep at completion returns null', () {
      final session = WizardSessionSnapshot(bikeType: BikeType.mostSpinBikes);
      expect(machine.nextStep(currentStep: WizardStepId.completion, session: session), isNull);
    });
  });

  group('previousStep', () {
    test('previousStep at welcome returns null', () {
      final session = WizardSessionSnapshot(bikeType: null);
      expect(machine.previousStep(currentStep: WizardStepId.welcome, session: session), isNull);
    });

    test('previousStep at every step in mostSpinBikes chain', () {
      final session = WizardSessionSnapshot(bikeType: BikeType.mostSpinBikes);
      final steps = machine.activeSteps(bikeType: BikeType.mostSpinBikes);
      for (int i = 1; i < steps.length; i++) {
        final prev = machine.previousStep(currentStep: steps[i], session: session);
        expect(prev, steps[i - 1], reason: 'from ${steps[i]} expected ${steps[i - 1]}');
      }
    });

    test('previousStep at every step in pelotonOriginal chain', () {
      final session = WizardSessionSnapshot(bikeType: BikeType.pelotonOriginal);
      final steps = machine.activeSteps(bikeType: BikeType.pelotonOriginal);
      for (int i = 1; i < steps.length; i++) {
        final prev = machine.previousStep(currentStep: steps[i], session: session);
        expect(prev, steps[i - 1]);
      }
    });
  });

  group('bike-type change after sideSwitch', () {
    test('going back from ss2kConnection, switching to mostSpinBikes skips sideSwitch', () {
      // Simulate: user was on pelotonOriginal, went back to bikeType, chose mostSpinBikes
      final newSession = WizardSessionSnapshot(bikeType: BikeType.mostSpinBikes);
      // From bikeType, next should be hardwareInstall (no sideSwitch in mostSpin)
      final next = machine.nextStep(currentStep: WizardStepId.bikeType, session: newSession);
      expect(next, WizardStepId.hardwareInstall);
      // From wiring, next should be ss2kConnection directly
      final afterWiring = machine.nextStep(currentStep: WizardStepId.wiring, session: newSession);
      expect(afterWiring, WizardStepId.ss2kConnection);
    });
  });

  group('metaFor', () {
    test('welcome: backDisabled=true, not skippable', () {
      final meta = machine.metaFor(WizardStepId.welcome);
      expect(meta.backDisabled, isTrue);
      expect(meta.isSkippable, isFalse);
    });

    test('bikeType: backDisabled=false, not skippable', () {
      final meta = machine.metaFor(WizardStepId.bikeType);
      expect(meta.backDisabled, isFalse);
      expect(meta.isSkippable, isFalse);
    });

    test('hrm: isSkippable=true', () {
      expect(machine.metaFor(WizardStepId.hrm).isSkippable, isTrue);
    });

    test('wifi: isSkippable=true', () {
      expect(machine.metaFor(WizardStepId.wifi).isSkippable, isTrue);
    });
  });
}
