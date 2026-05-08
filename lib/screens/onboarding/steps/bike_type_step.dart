import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';

class BikeTypeStep extends StatelessWidget {
  const BikeTypeStep({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WizardSession>();
    final machine = WizardStepMachine();

    return WizardScaffold(
      title: 'Select Your Bike',
      stepId: WizardStepId.bikeType,
      nextEnabled: session.bikeType != null,
      onNext: session.bikeType != null
          ? () {
              final next = machine.nextStep(
                currentStep: WizardStepId.bikeType,
                session: session.snapshot,
              );
              if (next != null) {
                final steps = machine.activeSteps(bikeType: session.bikeType);
                session.setStepIndex(steps.indexOf(next));
              }
            }
          : null,
      body: RadioGroup<BikeType>(
        groupValue: session.bikeType,
        onChanged: (val) {
          if (val != null) {
            session.bikeType = val;
            session.setStepIndex(session.currentStepIndex);
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'What type of spin bike do you have?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            _BikeTypeCard(
              bikeType: BikeType.mostSpinBikes,
              title: 'Bluetooth Compatible Spin Bikes',
              subtitle: 'Bowflex C6, Schwinn IC4, Yesoul S3, etc.',
              selected: session.bikeType == BikeType.mostSpinBikes,
            ),
            const SizedBox(height: 12),
            _BikeTypeCard(
              bikeType: BikeType.powerMeterBike,
              title: 'Power Meter',
              subtitle: 'Bikes equipped with power meter pedals or a crank power meter',
              selected: session.bikeType == BikeType.powerMeterBike,
            ),
            const SizedBox(height: 12),
            _BikeTypeCard(
              bikeType: BikeType.pelotonOriginal,
              title: 'Peloton Bike (Original)',
              subtitle: 'The original Peloton Bike',
              selected: session.bikeType == BikeType.pelotonOriginal,
            ),
            const SizedBox(height: 12),
            _BikeTypeCard(
              bikeType: BikeType.pelotonBikePlus,
              title: 'Peloton Bike+',
              subtitle: 'The Peloton Bike+ (not the original Peloton Bike)',
              selected: session.bikeType == BikeType.pelotonBikePlus,
            ),
          ],
        ),
      ),
    );
  }
}

class _BikeTypeCard extends StatelessWidget {
  final BikeType bikeType;
  final String title;
  final String subtitle;
  final bool selected;

  const _BikeTypeCard({
    required this.bikeType,
    required this.title,
    required this.subtitle,
    required this.selected,
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
      child: RadioListTile<BikeType>(
        value: bikeType,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        activeColor: colorScheme.primary,
      ),
    );
  }
}
