import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class DataSourceStep extends StatelessWidget {
  const DataSourceStep({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WizardSession>();
    final machine = WizardStepMachine();

    void advance() {
      final next = machine.nextStep(
        currentStep: WizardStepId.dataSource,
        session: session.snapshot,
      );
      if (next != null) {
        final steps = machine.activeSteps(bikeType: session.bikeType);
        session.setStepIndex(steps.indexOf(next));
      }
    }

    return WizardScaffold(
      title: 'Data Source',
      stepId: WizardStepId.dataSource,
      onNext: advance,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _DataSourceBody(session: session, onAdvance: advance),
      ),
    );
  }
}

class _DataSourceBody extends StatelessWidget {
  final WizardSession session;
  final VoidCallback onAdvance;

  const _DataSourceBody({required this.session, required this.onAdvance});

  @override
  Widget build(BuildContext context) {
    switch (session.bikeType) {
      case BikeType.pelotonBikePlus:
        return _PelotonBikePlusDataSource(onAdvance: onAdvance);
      case BikeType.pelotonOriginal:
        return const _WiredDataSource();
      default:
        return const _BLEPowerMeterDataSource();
    }
  }
}

class _BLEPowerMeterDataSource extends StatelessWidget {
  const _BLEPowerMeterDataSource();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pair a Power Meter',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 16),
        Text(
          'Your bike uses a BLE power meter as the data source. '
          'Make sure your power meter is active and in range.\n\n'
          'The SmartSpin2k will automatically scan for and connect to your paired power meter. '
          'Tap Continue to proceed to the data verification step.',
          style: TextStyle(fontSize: 16, height: 1.5),
        ),
      ],
    );
  }
}

class _WiredDataSource extends StatelessWidget {
  const _WiredDataSource();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wired Data Connection',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 16),
        Text(
          'Your Peloton Bike (Original) uses a wired sensor connection — no BLE pairing is needed. '
          'Data flows automatically through the sensor cable you connected earlier.\n\n'
          'Tap Continue to verify data is flowing.',
          style: TextStyle(fontSize: 16, height: 1.5),
        ),
      ],
    );
  }
}

class _PelotonBikePlusDataSource extends StatefulWidget {
  final VoidCallback onAdvance;
  const _PelotonBikePlusDataSource({required this.onAdvance});

  @override
  State<_PelotonBikePlusDataSource> createState() => _PelotonBikePlusDataSourceState();
}

class _PelotonBikePlusDataSourceState extends State<_PelotonBikePlusDataSource> {
  DataSource? _selected;

  @override
  Widget build(BuildContext context) {
    final session = context.read<WizardSession>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose Your Data Source',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          'The Peloton Bike+ supports two data source options:',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 16),
        _SourceCard(
          title: 'Grupetto (Recommended)',
          description: 'Uses the Peloton Bike+ cadence/power data directly. '
              'Start a ride on the Peloton tablet before the data verification step.',
          selected: _selected == DataSource.grupetto,
          onTap: () => setState(() {
            _selected = DataSource.grupetto;
            session.dataSourceChoice = DataSource.grupetto;
          }),
          trailing: TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Docs'),
            onPressed: () async {
              final url = Uri.parse('https://docs.smartspin2k.com/');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ),
        const SizedBox(height: 12),
        _SourceCard(
          title: 'BLE Power Meter',
          description: 'Pair a separate BLE power meter instead.',
          selected: _selected == DataSource.powerMeter,
          onTap: () => setState(() {
            _selected = DataSource.powerMeter;
            session.dataSourceChoice = DataSource.powerMeter;
          }),
        ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SourceCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: selected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).disabledColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(description,
                        style: const TextStyle(fontSize: 14, height: 1.4)),
                    if (trailing != null) ...[
                      const SizedBox(height: 8),
                      trailing!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
