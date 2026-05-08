enum BikeType { mostSpinBikes, pelotonBikePlus, pelotonOriginal }

enum DataSource { grupetto, powerMeter }

enum WizardStepId {
  welcome,
  bikeType,
  hardwareInstall,
  wiring,
  sideSwitch,
  ss2kConnection,
  dataSource,
  confirmDataFlowing,
  motorTest,
  physicalShifter,
  hrm,
  wifi,
  completion,
}

enum StepKind { informational, action, autoDetect, optional }

enum AutoAdvanceRule {
  bleConnected,
  powerAndCadenceStableFor3s,
  shifterEvent,
}

class WizardStepMeta {
  final WizardStepId id;
  final StepKind kind;
  final bool isSkippable;
  final bool backDisabled;
  final int? fallbackTimerMs;
  final AutoAdvanceRule? autoAdvanceRule;

  const WizardStepMeta({
    required this.id,
    required this.kind,
    this.isSkippable = false,
    this.backDisabled = false,
    this.fallbackTimerMs,
    this.autoAdvanceRule,
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

const _allStepsWithoutSideSwitch = [
  WizardStepId.welcome,
  WizardStepId.bikeType,
  WizardStepId.hardwareInstall,
  WizardStepId.wiring,
  WizardStepId.ss2kConnection,
  WizardStepId.dataSource,
  WizardStepId.confirmDataFlowing,
  WizardStepId.motorTest,
  WizardStepId.physicalShifter,
  WizardStepId.hrm,
  WizardStepId.wifi,
  WizardStepId.completion,
];

const _allStepsWithSideSwitch = [
  WizardStepId.welcome,
  WizardStepId.bikeType,
  WizardStepId.hardwareInstall,
  WizardStepId.wiring,
  WizardStepId.sideSwitch,
  WizardStepId.ss2kConnection,
  WizardStepId.dataSource,
  WizardStepId.confirmDataFlowing,
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
    kind: StepKind.informational,
    backDisabled: true,
  ),
  WizardStepId.bikeType: WizardStepMeta(
    id: WizardStepId.bikeType,
    kind: StepKind.action,
  ),
  WizardStepId.hardwareInstall: WizardStepMeta(
    id: WizardStepId.hardwareInstall,
    kind: StepKind.informational,
  ),
  WizardStepId.wiring: WizardStepMeta(
    id: WizardStepId.wiring,
    kind: StepKind.informational,
  ),
  WizardStepId.sideSwitch: WizardStepMeta(
    id: WizardStepId.sideSwitch,
    kind: StepKind.action,
  ),
  WizardStepId.ss2kConnection: WizardStepMeta(
    id: WizardStepId.ss2kConnection,
    kind: StepKind.action,
    autoAdvanceRule: AutoAdvanceRule.bleConnected,
  ),
  WizardStepId.dataSource: WizardStepMeta(
    id: WizardStepId.dataSource,
    kind: StepKind.action,
  ),
  WizardStepId.confirmDataFlowing: WizardStepMeta(
    id: WizardStepId.confirmDataFlowing,
    kind: StepKind.autoDetect,
    fallbackTimerMs: 30000,
    autoAdvanceRule: AutoAdvanceRule.powerAndCadenceStableFor3s,
  ),
  WizardStepId.motorTest: WizardStepMeta(
    id: WizardStepId.motorTest,
    kind: StepKind.action,
  ),
  WizardStepId.physicalShifter: WizardStepMeta(
    id: WizardStepId.physicalShifter,
    kind: StepKind.autoDetect,
    fallbackTimerMs: 30000,
    autoAdvanceRule: AutoAdvanceRule.shifterEvent,
  ),
  WizardStepId.hrm: WizardStepMeta(
    id: WizardStepId.hrm,
    kind: StepKind.optional,
    isSkippable: true,
  ),
  WizardStepId.wifi: WizardStepMeta(
    id: WizardStepId.wifi,
    kind: StepKind.optional,
    isSkippable: true,
  ),
  WizardStepId.completion: WizardStepMeta(
    id: WizardStepId.completion,
    kind: StepKind.informational,
  ),
};

class WizardStepMachine {
  WizardStepMachine();

  List<WizardStepId> activeSteps({required BikeType? bikeType}) {
    if (bikeType == null) return List.unmodifiable(_nullBikeTypeSteps);
    if (bikeType == BikeType.pelotonOriginal) {
      return List.unmodifiable(_allStepsWithSideSwitch);
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
