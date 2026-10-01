import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'workout_settings_theme.dart';
import 'workout_scroll_hint.dart';

/// Shared shell for workout settings, pickers, confirmations and ride export.
/// The whole shell scrolls, keeping actions reachable with large text or a
/// keyboard. List bodies get a bounded viewport so lazy lists remain lazy.
class WorkoutDialog extends StatelessWidget {
  const WorkoutDialog({
    super.key,
    required this.title,
    required this.content,
    this.icon = Icons.tune_rounded,
    this.eyebrow = 'YOUR WORKOUT',
    this.subtitle,
    this.actions = const [],
    this.showClose = false,
    this.listBody = false,
    this.showListScrollHint = true,
  });

  final Widget title;
  final Widget content;
  final IconData icon;
  final String eyebrow;
  final String? subtitle;
  final List<Widget> actions;
  final bool showClose;
  final bool listBody;

  /// Disable when the content places its own cue above a persistent toolbar.
  final bool showListScrollHint;

  @override
  Widget build(BuildContext context) {
    final theme = WorkoutSettingsTheme.resolve(Theme.of(context));
    final colors = theme.colorScheme;
    return Theme(
      data: theme,
      child: Dialog(
        constraints: BoxConstraints(
          maxWidth: listBody
              ? WorkoutSettingsTheme.browserWidth
              : WorkoutSettingsTheme.maxWidth,
        ),
        insetPadding: WorkoutSettingsTheme.inset,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            WorkoutSettingsTheme.dialogRadius,
          ),
          side: BorderSide(color: colors.outline.withValues(alpha: .18)),
        ),
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: WorkoutScrollHint(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: WorkoutSettingsTheme.headerPadding,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colors.primary.withValues(alpha: .12),
                        colors.surface,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: .10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(icon, color: colors.primary, size: 25),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: WorkoutSectionLabel(eyebrow, accent: true),
                          ),
                          if (showClose)
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close_rounded),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Semantics(
                        namesRoute: true,
                        header: true,
                        child: DefaultTextStyle(
                          style: theme.textTheme.headlineSmall!.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                          child: title,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: WorkoutSettingsTheme.bodyPadding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (listBody)
                        SizedBox(
                          height: math.max(
                            180,
                            math.min(
                              460,
                              MediaQuery.sizeOf(context).height * .55,
                            ),
                          ),
                          child: showListScrollHint
                              ? WorkoutScrollHint(child: content)
                              : content,
                        )
                      else
                        content,
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        WorkoutDialogActions(children: actions),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WorkoutDialogActions extends StatelessWidget {
  const WorkoutDialogActions({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => OverflowBar(
    alignment: MainAxisAlignment.end,
    spacing: 12,
    overflowSpacing: 10,
    children: children,
  );
}

class WorkoutSettingsPanel extends StatelessWidget {
  const WorkoutSettingsPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Ink(
      padding: const EdgeInsets.all(18),
      decoration: WorkoutSettingsTheme.panel(Theme.of(context).colorScheme),
      child: child,
    ),
  );
}

/// Browser rows put thumbnails above the copy when horizontal space is scarce.
class WorkoutOptionTile extends StatelessWidget {
  const WorkoutOptionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final copy = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle.merge(
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  child: title,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    child: subtitle!,
                  ),
                ],
              ],
            );
            if (constraints.maxWidth < 400) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (leading != null || trailing != null) ...[
                    Row(
                      children: [
                        if (leading != null) Flexible(child: leading!),
                        if (trailing != null) ...[const Spacer(), trailing!],
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  copy,
                ],
              );
            }
            return Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 14)],
                Expanded(child: copy),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            );
          },
        ),
      ),
    ),
  );
}

class WorkoutSectionLabel extends StatelessWidget {
  const WorkoutSectionLabel(this.text, {super.key, this.accent = false});
  final String text;
  final bool accent;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: accent ? FontWeight.w800 : FontWeight.w700,
      letterSpacing: accent ? 1.4 : 1,
      color: accent
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class WorkoutSettingSlider extends StatelessWidget {
  const WorkoutSettingSlider({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => WorkoutSettingsPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(valueLabel, style: Theme.of(context).textTheme.titleLarge),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueLabel,
          semanticFormatterCallback: (_) => '$label: $valueLabel',
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class WorkoutActionTile extends StatelessWidget {
  const WorkoutActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = primary ? colors.onPrimary : colors.onSurface;
    return Material(
      color: primary ? colors.primary : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WorkoutSettingsTheme.actionRadius),
        side: BorderSide(
          color: primary
              ? colors.primary
              : colors.outline.withValues(alpha: .25),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 25,
                  color: primary ? foreground : colors.primary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: primary
                                ? foreground.withValues(alpha: .9)
                                : colors.onSurfaceVariant,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, size: 18, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
