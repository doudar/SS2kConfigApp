enum BikeType { mostSpinBikes, pelotonBikePlus, pelotonOriginal, powerMeterBike }

enum DataSource { grupetto, powerMeter }

enum SideSwitchMode { tabletMode, headlessMode }

enum PelotonTabletApp { peloton, grupetto }

enum WizardStepId {
  welcome,
  bikeType,
  hardwareInstall,
  hardwareInstallArm,
  hardwareInstallKnobInsert,
  hardwareInstallMount,
  hardwareInstallShifter,
  hardwareInstallCable,
  hardwareInstallPower,
  wiring,
  sensorWiring,
  sensorWiringHarness,
  sensorWiringConnected,
  sideSwitch,
  sideSwitchPosition,
  sideSwitchCable,
  sideSwitchClip,
  ss2kConnection,
  dataSource,
  bikeDataTest,
  motorTest,
  physicalShifter,
  hrm,
  wifi,
  completion,
}

class WizardStepMeta {
  final WizardStepId id;
  final bool isSkippable;
  final bool backDisabled;

  const WizardStepMeta({
    required this.id,
    this.isSkippable = false,
    this.backDisabled = false,
  });
}

class WizardSessionSnapshot {
  final BikeType? bikeType;
  final DataSource? dataSourceChoice;
  final bool hrmSkipped;
  final bool wifiSkipped;

  const WizardSessionSnapshot({
    this.bikeType,
    this.dataSourceChoice,
    this.hrmSkipped = false,
    this.wifiSkipped = false,
  });
}

const _hardwareInstallSteps = [
  WizardStepId.hardwareInstall,
  WizardStepId.hardwareInstallArm,
  WizardStepId.hardwareInstallKnobInsert,
  WizardStepId.hardwareInstallMount,
  WizardStepId.hardwareInstallShifter,
  WizardStepId.hardwareInstallCable,
  WizardStepId.hardwareInstallPower,
];

const _sensorWiringSteps = [
  WizardStepId.sensorWiring,
  WizardStepId.sensorWiringHarness,
  WizardStepId.sensorWiringConnected,
];

const _sideSwitchSteps = [
  WizardStepId.sideSwitch,
  WizardStepId.sideSwitchPosition,
  WizardStepId.sideSwitchCable,
  WizardStepId.sideSwitchClip,
];

const _allStepsWithoutSideSwitch = [
  WizardStepId.welcome,
  WizardStepId.bikeType,
  ..._hardwareInstallSteps,
  WizardStepId.wiring,
  WizardStepId.ss2kConnection,
  WizardStepId.dataSource,
  WizardStepId.bikeDataTest,
  WizardStepId.motorTest,
  WizardStepId.physicalShifter,
  WizardStepId.hrm,
  WizardStepId.wifi,
  WizardStepId.completion,
];

// Peloton Original has no real data-source choice (wired sensors only), so
// the dataSource step is folded into bikeDataTest's pre-ride guidance.
const _pelotonOriginalSteps = [
  WizardStepId.welcome,
  WizardStepId.bikeType,
  ..._hardwareInstallSteps,
  WizardStepId.wiring,
  ..._sensorWiringSteps,
  ..._sideSwitchSteps,
  WizardStepId.ss2kConnection,
  WizardStepId.bikeDataTest,
  WizardStepId.motorTest,
  WizardStepId.physicalShifter,
  WizardStepId.hrm,
  WizardStepId.wifi,
  WizardStepId.completion,
];

const _nullBikeTypeSteps = [
  WizardStepId.welcome,
  WizardStepId.bikeType,
];

const _stepMetaTable = <WizardStepId, WizardStepMeta>{
  WizardStepId.welcome: WizardStepMeta(
    id: WizardStepId.welcome,
    backDisabled: true,
  ),
  WizardStepId.bikeType: WizardStepMeta(id: WizardStepId.bikeType),
  WizardStepId.hardwareInstall: WizardStepMeta(id: WizardStepId.hardwareInstall),
  WizardStepId.hardwareInstallArm:
      WizardStepMeta(id: WizardStepId.hardwareInstallArm),
  WizardStepId.hardwareInstallKnobInsert:
      WizardStepMeta(id: WizardStepId.hardwareInstallKnobInsert),
  WizardStepId.hardwareInstallMount:
      WizardStepMeta(id: WizardStepId.hardwareInstallMount),
  WizardStepId.hardwareInstallShifter:
      WizardStepMeta(id: WizardStepId.hardwareInstallShifter),
  WizardStepId.hardwareInstallCable:
      WizardStepMeta(id: WizardStepId.hardwareInstallCable),
  WizardStepId.hardwareInstallPower:
      WizardStepMeta(id: WizardStepId.hardwareInstallPower),
  WizardStepId.wiring: WizardStepMeta(id: WizardStepId.wiring),
  WizardStepId.sensorWiring: WizardStepMeta(id: WizardStepId.sensorWiring),
  WizardStepId.sensorWiringHarness:
      WizardStepMeta(id: WizardStepId.sensorWiringHarness),
  WizardStepId.sensorWiringConnected:
      WizardStepMeta(id: WizardStepId.sensorWiringConnected),
  WizardStepId.sideSwitch: WizardStepMeta(id: WizardStepId.sideSwitch),
  WizardStepId.sideSwitchPosition:
      WizardStepMeta(id: WizardStepId.sideSwitchPosition),
  WizardStepId.sideSwitchCable:
      WizardStepMeta(id: WizardStepId.sideSwitchCable),
  WizardStepId.sideSwitchClip:
      WizardStepMeta(id: WizardStepId.sideSwitchClip),
  WizardStepId.ss2kConnection: WizardStepMeta(id: WizardStepId.ss2kConnection),
  WizardStepId.dataSource: WizardStepMeta(id: WizardStepId.dataSource),
  WizardStepId.bikeDataTest: WizardStepMeta(id: WizardStepId.bikeDataTest),
  WizardStepId.motorTest: WizardStepMeta(id: WizardStepId.motorTest),
  WizardStepId.physicalShifter: WizardStepMeta(id: WizardStepId.physicalShifter),
  WizardStepId.hrm: WizardStepMeta(
    id: WizardStepId.hrm,
    isSkippable: true,
  ),
  WizardStepId.wifi: WizardStepMeta(
    id: WizardStepId.wifi,
    isSkippable: true,
  ),
  WizardStepId.completion: WizardStepMeta(id: WizardStepId.completion),
};

class WizardStepMachine {
  WizardStepMachine();

  List<WizardStepId> activeSteps({required BikeType? bikeType}) {
    if (bikeType == null) return List.unmodifiable(_nullBikeTypeSteps);
    if (bikeType == BikeType.pelotonOriginal) {
      return List.unmodifiable(_pelotonOriginalSteps);
    }
    return List.unmodifiable(_allStepsWithoutSideSwitch);
  }

  WizardStepId? nextStep({
    required WizardStepId currentStep,
    required WizardSessionSnapshot session,
  }) {
    if (currentStep == WizardStepId.bikeType && session.bikeType == null) {
      throw StateError('cannot advance from bikeType without a selection');
    }
    final steps = activeSteps(bikeType: session.bikeType);
    final index = steps.indexOf(currentStep);
    if (index < 0 || index >= steps.length - 1) return null;
    return steps[index + 1];
  }

  WizardStepId? previousStep({
    required WizardStepId currentStep,
    required WizardSessionSnapshot session,
  }) {
    if (currentStep == WizardStepId.welcome) return null;
    final steps = activeSteps(bikeType: session.bikeType);
    final index = steps.indexOf(currentStep);
    if (index <= 0) return null;
    return steps[index - 1];
  }

  WizardStepMeta metaFor(WizardStepId id) {
    return _stepMetaTable[id]!;
  }
}
