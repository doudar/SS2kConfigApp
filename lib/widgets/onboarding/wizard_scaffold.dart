import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/onboarding/wizard_step_machine.dart';
import '../../utils/onboarding/wizard_session.dart';
import '../../utils/onboarding/onboarding_state.dart';
import 'onboarding_panel.dart';

class WizardScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final VoidCallback? onNext;
  final String nextLabel;
  final bool nextEnabled;
  final bool showSkip;
  final VoidCallback? onSkip;
  final bool showSkipSetup;
  final WizardStepId stepId;
  final VoidCallback? onBack;

  const WizardScaffold({
    Key? key,
    required this.title,
    required this.body,
    required this.stepId,
    this.onNext,
    this.nextLabel = 'Continue',
    this.nextEnabled = true,
    this.showSkip = false,
    this.onSkip,
    this.showSkipSetup = true,
    this.onBack,
  }) : super(key: key);

  Future<void> _skipSetup(BuildContext context) async {
    await OnboardingState.markCompleted();
    if (!context.mounted) return;
    // markCompleted() fires OnboardingState.completedNotifier, which main.dart
    // listens to and rebuilds its home route to ScanScreen. So we must NOT push
    // a fresh ScanScreen here: when the wizard was opened via "Guided Setup" the
    // app already has a ScanScreen mounted as home, and a second one would share
    // the static Snackbar.snackBarKeyB GlobalKey, crashing finalizeTree.
    // Instead, if the wizard was pushed on top of an existing screen, pop back to
    // it; on first launch (wizard is the home route) the reactive rebuild handles it.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WizardSession>();
    final machine = WizardStepMachine();
    final meta = machine.metaFor(stepId);
    final steps = machine.activeSteps(bikeType: session.bikeType);
    final totalSteps = steps.length;
    final currentIndex = steps.indexOf(stepId);
    final progress = currentIndex >= 0 && totalSteps > 0
        ? (currentIndex + 1) / totalSteps
        : 0.0;
    final theme = Theme.of(context);
    final style = OnboardingStyle.of(context);
    final headerForeground = style.foreground;

    return Scaffold(
      backgroundColor: style.scaffoldBackground,
      appBar: AppBar(
        toolbarHeight: 92,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        foregroundColor: headerForeground,
        automaticallyImplyLeading: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16),
            ),
            gradient: style.appBarGradient,
            border: Border(
              bottom: BorderSide(
                color: Colors.red.withValues(alpha: style.isLight ? 0.20 : 0.35),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black.withValues(alpha: style.isLight ? 0.10 : 0.18),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        titleSpacing: 0,
        title: Padding(
          padding: EdgeInsets.only(
            left: meta.backDisabled ? 16 : 8,
            right: 8,
          ),
          child: _WizardHeaderTitle(
            title: title,
            currentStep: currentIndex >= 0 ? currentIndex + 1 : null,
            totalSteps: totalSteps,
            optional: meta.isSkippable,
          ),
        ),
        leading: meta.backDisabled
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: onBack ??
                    () {
                      final prev = machine.previousStep(
                        currentStep: stepId,
                        session: session.snapshot,
                      );
                      if (prev != null) {
                        final prevIndex = steps.indexOf(prev);
                        // The OnboardingWizard's PageController is notified via session
                        session.setStepIndex(prevIndex);
                      }
                    },
              ),
        actions: [
          if (showSkipSetup)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _HeaderActionChip(
                icon: Icons.close,
                label: 'Exit Setup',
                foreground: headerForeground,
                onTap: () => _skipSetup(context),
              ),
            ),
          if (showSkip)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _HeaderActionChip(
                icon: Icons.skip_next,
                label: 'Skip',
                foreground: headerForeground,
                onTap: onSkip,
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(16),
          child: currentIndex >= 0
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: progress,
                      backgroundColor: headerForeground.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        style.isLight
                            ? Colors.red.shade700
                            : Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: style.scaffoldGradient,
        ),
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium?.copyWith(
                color: style.body,
              ) ??
              TextStyle(color: style.body),
          child: IconTheme(
            data: IconThemeData(color: style.foreground),
            child: body,
          ),
        ),
      ),
      bottomNavigationBar: onNext != null
          ? SafeArea(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: style.bottomBarBackground,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: style.isLight ? 0.12 : 0.42),
                      blurRadius: 20,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: SizedBox(
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: style.buttonGradient(nextEnabled),
                        border: Border.all(
                          color: nextEnabled
                              ? Colors.red.withValues(
                                  alpha: style.isLight ? 0.34 : 0.28,
                                )
                              : style.foreground.withValues(alpha: 0.12),
                        ),
                        boxShadow: nextEnabled
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                                BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.14),
                                  blurRadius: 10,
                                  spreadRadius: -2,
                                ),
                              ]
                            : null,
                      ),
                      child: ElevatedButton.icon(
                        onPressed: nextEnabled ? onNext : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(nextLabel),
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          disabledForegroundColor: style.foreground
                              .withValues(alpha: style.isLight ? 0.38 : 0.38),
                          shadowColor: Colors.transparent,
                          textStyle: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _HeaderActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;
  final VoidCallback? onTap;

  const _HeaderActionChip({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SizedBox(
        height: 30,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: foreground.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: foreground.withValues(alpha: 0.22),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: foreground),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: foreground.withValues(alpha: 0.90),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WizardHeaderTitle extends StatelessWidget {
  final String title;
  final int? currentStep;
  final int totalSteps;
  final bool optional;

  const _WizardHeaderTitle({
    required this.title,
    required this.currentStep,
    required this.totalSteps,
    required this.optional,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = OnboardingStyle.of(context);
    final foreground = style.foreground;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          currentStep == null
              ? 'Guided Setup'
              : 'Step $currentStep of $totalSteps',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: foreground.withValues(alpha: 0.76),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  shadows: style.isLight
                      ? null
                      : const [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                        ],
                ),
              ),
            ),
            if (optional) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: foreground.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: foreground.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  'Optional',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: foreground.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
