import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/onboarding/wizard_step_machine.dart';
import '../../../utils/onboarding/wizard_session.dart';
import '../../../widgets/onboarding/wizard_scaffold.dart';
import '../../../widgets/onboarding/instruction_step_card.dart';

enum _Phase { picker, instructions }

class SideSwitchStep extends StatefulWidget {
  const SideSwitchStep({Key? key}) : super(key: key);

  @override
  State<SideSwitchStep> createState() => _SideSwitchStepState();
}

class _SideSwitchStepState extends State<SideSwitchStep> {
  SideSwitchMode? _selected;
  _Phase _phase = _Phase.picker;

  void _advanceWizard(WizardSession session) {
    final machine = WizardStepMachine();
    final next = machine.nextStep(currentStep: WizardStepId.sideSwitch, session: session.snapshot);
    if (next != null) {
      final steps = machine.activeSteps(bikeType: session.bikeType);
      session.setStepIndex(steps.indexOf(next));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<WizardSession>();
    final isPicker = _phase == _Phase.picker;

    return WizardScaffold(
      title: 'Side Switch',
      stepId: WizardStepId.sideSwitch,
      nextEnabled: isPicker ? _selected != null : true,
      onBack: isPicker ? null : () => setState(() => _phase = _Phase.picker),
      onNext: isPicker
          ? (_selected == null
                ? null
                : () {
                    session.sideSwitchMode = _selected;
                    setState(() => _phase = _Phase.instructions);
                  })
          : () => _advanceWizard(session),
      body: isPicker ? _buildPicker() : _buildInstructions(),
    );
  }

  Widget _buildPicker() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How do you want to use your bike?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text(
            'The SmartSpin2k can work alongside your Peloton tablet, or replace it '
            'entirely. Pick the option that fits how you want to ride.',
            style: TextStyle(fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 20),
          _ModeCard(
            label: 'Tablet Mode',
            switchPosition: 'Switch UP',
            recommended: true,
            description:
                'Best if you (or anyone in your household) wants the '
                'option to take a Peloton class. Required if using Grupetto'
                'with a wired connection',
            selected: _selected == SideSwitchMode.tabletMode,
            onTap: () => setState(() => _selected = SideSwitchMode.tabletMode),
          ),
          const SizedBox(height: 12),
          _ModeCard(
            label: 'Headless Mode',
            switchPosition: 'Switch DOWN',
            recommended: false,
            description:
                'The SmartSpin2k talks to your bike directly. Use any training app '
                'on the tablet — or leave the tablet off entirely. Recommended if you never '
                'plan to take a Peloton class or use Grupetto on your tablet.',
            selected: _selected == SideSwitchMode.headlessMode,
            onTap: () => setState(() => _selected = SideSwitchMode.headlessMode),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    final isTablet = _selected == SideSwitchMode.tabletMode;
    final headerLabel = isTablet ? 'Tablet Mode setup' : 'Headless Mode setup';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(headerLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Change selection'),
                  onPressed: () => setState(() => _phase = _Phase.picker),
                ),
              ],
            ),
          ),
          if (isTablet) ..._tabletInstructions() else ..._headlessInstructions(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  List<Widget> _tabletInstructions() {
    return const [
      InstructionStepCard(
        stepNumber: 1,
        title: 'Flip the side switch UP',
        body: 'On the side of your SmartSpin2k, slide the switch to the UP position.',
        imageAsset: 'assets/images/side_switch_up.svg',
        imagePlaceholderLabel: 'Photo: SmartSpin2k side switch in UP position',
      ),
      SizedBox(height: 16),
      InstructionStepCard(
        stepNumber: 2,
        title: 'Connect the "Peloton Tablet" cable',
        body:
            'Plug the SmartSpin2k cable labeled "Peloton Tablet" into the back of '
            'your bike\'s tablet — into the same port the original sensor wire used.',
        imageAsset: 'assets/images/side_switch_tablet_cable_connected.svg',
        imagePlaceholderLabel: 'Photo: Peloton Tablet cable plugged into back of tablet',
      ),
      SizedBox(height: 16),
      InstructionStepCard(
        stepNumber: 3,
        title: 'Re-latch the cable retention clip',
        body: 'Snap the cable retention clip back into place to keep the wires secure.',
        imageAsset: 'assets/images/side_switch_tablet_clip_latched.svg',
        imagePlaceholderLabel: 'Photo: retention clip latched over wires',
      ),
    ];
  }

  List<Widget> _headlessInstructions() {
    return const [
      InstructionStepCard(
        stepNumber: 1,
        title: 'Flip the side switch DOWN',
        body: 'On the side of your SmartSpin2k, slide the switch to the DOWN position.',
        imageAsset: 'assets/images/side_switch_down.svg',
        imagePlaceholderLabel: 'Photo: SmartSpin2k side switch in DOWN position',
      ),
      SizedBox(height: 16),
      InstructionStepCard(
        stepNumber: 2,
        title: 'Leave the "Peloton Tablet" cable disconnected',
        body:
            'Do not plug the SmartSpin2k\'s "Peloton Tablet" cable into your bike. '
            'Coil it up out of the way.',
        imageAsset: 'assets/images/side_switch_tablet_cable_unused.svg',
        imagePlaceholderLabel: 'Photo: unconnected Peloton Tablet cable coiled aside',
      ),
      SizedBox(height: 16),
      InstructionStepCard(
        stepNumber: 3,
        title: 'Re-latch the cable retention clip',
        body: 'Snap the cable retention clip back into place to keep the sensor wire secure.',
        imageAsset: 'assets/images/side_switch_clip_latched.svg',
        imagePlaceholderLabel: 'Photo: retention clip latched over wires',
      ),
    ];
  }
}

class _ModeCard extends StatelessWidget {
  final String label;
  final String switchPosition;
  final String description;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  const _ModeCard({
    required this.label,
    required this.switchPosition,
    required this.description,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: selected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? colorScheme.primary : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? colorScheme.primary : Theme.of(context).disabledColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(
                          '· $switchPosition',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).hintColor,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        if (recommended)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Recommended',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.primary),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(description, style: const TextStyle(fontSize: 14, height: 1.4)),
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
