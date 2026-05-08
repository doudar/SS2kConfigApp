import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show PageController;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'wizard_step_machine.dart';

class WizardSession extends ChangeNotifier {
  int currentStepIndex = 0;
  BikeType? bikeType;
  DataSource? dataSourceChoice;
  BluetoothDevice? connectedDevice;
  bool motorTestPassed = false;
  bool physicalShifterSeen = false;
  bool hrmSkipped = false;
  bool wifiSkipped = false;
  // Set by OnboardingWizard so steps can jump pages (e.g. Start Over).
  PageController? pageController;

  void setStepIndex(int index) {
    currentStepIndex = index;
    notifyListeners();
  }

  void reset() {
    currentStepIndex = 0;
    bikeType = null;
    dataSourceChoice = null;
    connectedDevice = null;
    motorTestPassed = false;
    physicalShifterSeen = false;
    hrmSkipped = false;
    wifiSkipped = false;
    notifyListeners();
  }

  WizardSessionSnapshot get snapshot => WizardSessionSnapshot(
        bikeType: bikeType,
        dataSourceChoice: dataSourceChoice,
        hrmSkipped: hrmSkipped,
        wifiSkipped: wifiSkipped,
      );
}
