import 'dart:async';
import 'dart:io' as io show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../../../utils/constants.dart';
import '../../../utils/device_data.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../utils/snackbar.dart';
import '../../../utils/demo.dart';
import '../../../utils/dircon_discovery.dart';
import '../../../utils/smartspin_scan_result.dart';
import '../../../utils/nearby_ble_devices.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';
import '../../../widgets/scan_result_tile.dart';

class Ss2kConnectionStep extends StatefulWidget {
  const Ss2kConnectionStep({Key? key}) : super(key: key);

  @override
  State<Ss2kConnectionStep> createState() => _Ss2kConnectionStepState();
}

class _Ss2kConnectionStepState extends State<Ss2kConnectionStep> {
  List<ScanResult> _scanResults = [];
  bool _bleScanning = false;
  final _networkDiscovery = DirConDiscovery();
  bool get _isScanning => _bleScanning || _networkDiscovery.isScanning;
  void _networkChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _stopScan() async {
    await _networkDiscovery.stop();
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
  }

  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  @override
  void initState() {
    super.initState();
    _networkDiscovery.addListener(_networkChanged);
    // In demo mode there is no real device to scan for: inject the simulated
    // SmartSpin2k and skip the BLE subscriptions (a real scan would emit empty
    // results and wipe the demo tile).
    if (demoModeBypass.value) {
      _scanResults = [DemoDevice().simulateSmartSpin2kScan()];
      return;
    }
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        NearbyBleDevices.instance.observeAll(results);
        DeviceDataManager.refreshNearbyDevices();
        if (mounted) setState(() => _scanResults = results);
      },
      onError: (e) {
        Snackbar.show(ABC.b, prettyException("Scan Error:", e), success: false);
      },
    );
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      if (mounted) setState(() => _bleScanning = state);
    });
    _startScan();
  }

  @override
  void dispose() {
    _networkDiscovery.removeListener(_networkChanged);
    _networkDiscovery.dispose();
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    unawaited(_networkDiscovery.start());
    try {
      if (kIsWeb) {
        await FlutterBluePlus.startScan(
          withServices: [Guid(csUUID)],
          timeout: const Duration(seconds: 15),
        );
      } else {
        int divisor = !kIsWeb && io.Platform.isAndroid ? 8 : 1;
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 15),
          continuousUpdates: true,
          continuousDivisor: divisor,
        );
      }
    } catch (e) {
      Snackbar.show(
        ABC.b,
        prettyException("Start Scan Error:", e),
        success: false,
      );
    }
  }

  Future<void> _onConnectPressed(
    SmartSpinScanResult result,
    WizardSession session,
  ) async {
    final device = result.device;
    // In demo mode, seed the simulated device instead of attempting a real BLE
    // connection. Downstream steps read this device's DeviceData and behave like
    // the main app's demo mode.
    if (demoModeBypass.value) {
      DeviceDataManager.forDevice(device).setupDemoData();
    } else {
      await _stopScan();
      final deviceData = DeviceDataManager.forDevice(device);
      deviceData.applyScanResult(result);
      if (deviceData.isUserDisconnect) {
        deviceData.isUserDisconnect = false;
      }

      if (!deviceData.isTransportActive)
        unawaited(
          deviceData.connectPreferred(device).catchError((Object e) {
            Snackbar.show(
              ABC.c,
              prettyException("Connect Error:", e),
              success: false,
            );
          }),
        );
    }

    session.connectedDevice = device;
    final machine = WizardStepMachine();
    final next = machine.nextStep(
      currentStep: WizardStepId.ss2kConnection,
      session: session.snapshot,
    );
    if (next != null) {
      final steps = machine.activeSteps(bikeType: session.bikeType);
      session.setStepIndex(steps.indexOf(next));
    }
  }

  List<SmartSpinScanResult> get _filteredResults => SmartSpinScanResult.merge(
    _scanResults,
    _networkDiscovery.endpoints,
    includeAllBle: kIsWeb,
  ).map(DeviceDataManager.reuseConnectedIdentity).toList();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WizardSession>();

    return WizardScaffold(
      title: 'Connect SmartSpin2k',
      stepId: WizardStepId.ss2kConnection,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                ..._filteredResults.map(
                  (r) => ScanResultTile(
                    key: ValueKey(r.device.remoteId.str),
                    result: r,
                    onTap: () => _onConnectPressed(r, session),
                  ),
                ),
                if (_filteredResults.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('Scanning for SmartSpin2k...')),
                  ),
              ],
            ),
          ),
          // Scanning is meaningless in demo mode and would clear the demo tile.
          if (!demoModeBypass.value)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ElevatedButton.icon(
                  onPressed: _isScanning ? _stopScan : _startScan,
                  icon: Icon(_isScanning ? Icons.stop : Icons.search),
                  label: Text(_isScanning ? 'Stop Scan' : 'Scan Again'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
