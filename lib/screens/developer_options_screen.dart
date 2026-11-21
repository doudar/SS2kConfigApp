import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../utils/constants.dart';
import '../utils/device_data.dart';
import '../widgets/ss2k_app_bar.dart';

class DeveloperOptionsScreen extends StatefulWidget {
  const DeveloperOptionsScreen({super.key, required this.device});
  final BluetoothDevice device;
  @override
  State<DeveloperOptionsScreen> createState() => _DeveloperOptionsState();
}

class _DeveloperOptionsState extends State<DeveloperOptionsScreen> {
  late final data = DeviceDataManager.forDevice(widget.device);
  final sliders = <String, double>{};
  final timers = <String, Timer>{};
  final writing = <String>{};
  StreamSubscription<CharacteristicChangeEvent>? subscription;
  final random = Random();

  @override
  void initState() {
    super.initState();
    subscription = data.characteristicChanges.listen((event) {
      if (mounted) setState(() {});
    });
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    for (final name in [
      simulateCadVname,
      simulatedCadVname,
      simulateHrVname,
      simulatedHrVname,
      simulateWattsVname,
      simulatedWattsVname,
      FTMSModeVname,
      simulateTargetWattsVname,
      simulatedTargetWattsVname,
    ]) {
      if (!mounted) return;
      await data.requestSetting(widget.device, name);
    }
  }

  @override
  void dispose() {
    for (final timer in timers.values) {
      timer.cancel();
    }
    subscription?.cancel();
    super.dispose();
  }

  String read(String name) => data.getVnameValue(name);
  Future<void> write(String name, String value) async {
    if (!writing.add(name)) return;
    final entry = data.customCharacteristic.firstWhere(
      (c) => c['vName'] == name,
    );
    try {
      await data.writeToSS2kStrict(widget.device, entry, s: value);
      if (data.isSimulated) entry['value'] = value;
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SmartSpin2k could not apply this change. $error'),
          ),
        );
    } finally {
      writing.remove(name);
      if (mounted) setState(() {});
    }
  }

  Widget simulation(
    String label,
    String flag,
    String name,
    String unit,
    int minimum,
    int maximum, {
    int variation = 0,
  }) {
    final enabled = read(flag) == 'true';
    final current =
        (sliders[name] ?? double.tryParse(read(name)) ?? minimum.toDouble())
            .clamp(minimum.toDouble(), maximum.toDouble())
            .toDouble();
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: Text(label),
            value: enabled,
            onChanged: (on) async {
              if (!on) timers.remove(name)?.cancel();
              await write(flag, on.toString());
            },
          ),
          if (enabled) ...[
            Text('${current.round()} $unit'),
            Slider(
              value: current,
              min: minimum.toDouble(),
              max: maximum.toDouble(),
              divisions: maximum - minimum,
              onChanged: (v) => setState(() => sliders[name] = v),
              onChangeEnd: (v) async {
                await write(name, v.round().toString());
                if (mounted) setState(() => sliders.remove(name));
              },
            ),
            if (variation > 0)
              SwitchListTile(
                title: const Text('Vary automatically'),
                value: timers.containsKey(name),
                onChanged: (on) {
                  setState(() {
                    timers.remove(name)?.cancel();
                    if (on)
                      timers[name] = Timer.periodic(
                        const Duration(seconds: 1),
                        (_) {
                          if (!data.isSimulated && !data.isTransportActive ||
                              read(flag) != 'true') {
                            timers.remove(name)?.cancel();
                            if (mounted) setState(() {});
                            return;
                          }
                          final previous = int.tryParse(read(name)) ?? minimum;
                          final next =
                              (previous +
                                      random.nextInt(2 * variation + 1) -
                                      variation)
                                  .clamp(minimum, maximum);
                          unawaited(write(name, next.toString()));
                        },
                      );
                  });
                },
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: SS2KAppBar(device: widget.device, title: 'Developer Options'),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        simulation(
          'Simulate cadence',
          simulateCadVname,
          simulatedCadVname,
          'rpm',
          0,
          180,
          variation: 3,
        ),
        simulation(
          'Simulate heart rate',
          simulateHrVname,
          simulatedHrVname,
          'bpm',
          40,
          250,
        ),
        simulation(
          'Simulate power',
          simulateWattsVname,
          simulatedWattsVname,
          'W',
          0,
          600,
          variation: 5,
        ),
        SwitchListTile(
          title: const Text('ERG mode'),
          value: read(FTMSModeVname) == '5',
          onChanged: (on) => write(FTMSModeVname, on ? '5' : '0'),
        ),
        if (read(FTMSModeVname) == '5')
          simulation(
            'Simulate target power',
            simulateTargetWattsVname,
            simulatedTargetWattsVname,
            'W',
            0,
            600,
          ),
      ],
    ),
  );
}
