import 'dart:async';
import 'dart:io' as io show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../../../utils/constants.dart';
import '../../../utils/bledata.dart';
import '../../../utils/extra.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../utils/snackbar.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';
import '../../../widgets/scan_result_tile.dart';

class Ss2kConnectionStep extends StatefulWidget {
  const Ss2kConnectionStep({Key? key}) : super(key: key);

  @override
  State<Ss2kConnectionStep> createState() => _Ss2kConnectionStepState();
}

class _Ss2kConnectionStepState extends State<Ss2kConnectionStep> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;

  final Guid _csGuid = Guid(csUUID);

  @override
  void initState() {
    super.initState();
    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) setState(() => _scanResults = results);
    }, onError: (e) {
      Snackbar.show(ABC.b, prettyException("Scan Error:", e), success: false);
    });
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      if (mounted) setState(() => _isScanning = state);
    });
    _startScan();
  }

  @override
  void dispose() {
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
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
      Snackbar.show(ABC.b, prettyException("Start Scan Error:", e), success: false);
    }
  }

  void _onConnectPressed(BluetoothDevice device, WizardSession session) {
    if (FlutterBluePlus.isScanningNow) FlutterBluePlus.stopScan();
    try {
      if (BLEDataManager.forDevice(device).isUserDisconnect) {
        BLEDataManager.forDevice(device).isUserDisconnect = false;
      }
    } catch (_) {}

    device.connectAndUpdateStream().catchError((e) {
      Snackbar.show(ABC.c, prettyException("Connect Error:", e), success: false);
    });

    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected && mounted) {
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
    });
  }

  List<ScanResult> get _filteredResults {
    if (kIsWeb) return _scanResults;
    return _scanResults.where((r) {
      final adv = r.advertisementData;
      return adv.serviceUuids.any(
        (uuid) => uuid == _csGuid || uuid.str.toLowerCase() == csUUID.toLowerCase(),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WizardSession>();

    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyB,
      child: WizardScaffold(
        title: 'Connect SmartSpin2k',
        stepId: WizardStepId.ss2kConnection,
        body: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  ..._filteredResults.map((r) => ScanResultTile(
                        result: r,
                        onTap: () => _onConnectPressed(r.device, session),
                      )),
                  if (_filteredResults.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Scanning for SmartSpin2k...')),
                    ),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ElevatedButton.icon(
                  onPressed: _isScanning ? () => FlutterBluePlus.stopScan() : _startScan,
                  icon: Icon(_isScanning ? Icons.stop : Icons.search),
                  label: Text(_isScanning ? 'Stop Scan' : 'Scan Again'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
