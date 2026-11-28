import 'package:flutter/material.dart';
import 'workout_settings_theme.dart';
import 'workout_scroll_hint.dart';

/// Shared shell for workout settings, pickers, confirmations and ride export.
/// Navigation stays visible while long forms and lists scroll in the body.
class WorkoutDialog extends StatelessWidget {
  const WorkoutDialog({
    super.key,
    required this.title,
    required this.content,
    this.icon = Icons.tune_rounded,
    this.eyebrow,
    this.subtitle,
    this.actions = const [],
    this.showClose = false,
    this.listBody = false,
    this.maxWidth,
    this.showListScrollHint = true,
  });

  final Widget title;
  final Widget content;
  final IconData icon;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;
  final bool showClose;
  final bool listBody;
  final double? maxWidth;

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
          maxWidth:
              maxWidth ??
              (listBody
                  ? WorkoutSettingsTheme.browserWidth
                  : WorkoutSettingsTheme.maxWidth),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final heading = Semantics(
              namesRoute: true,
              header: true,
              child: DefaultTextStyle(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge!.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
                child: title,
              ),
            );
            final description = subtitle == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      subtitle!,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  );
            final body = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (description != null) description,
                if (listBody)
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 520),
                      child: showListScrollHint
                          ? WorkoutScrollHint(child: content)
                          : content,
                    ),
                  )
                else
                  content,
              ],
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: colors.primary.withValues(alpha: .06),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: colors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (eyebrow != null)
                              WorkoutSectionLabel(eyebrow!, accent: true),
                            heading,
                          ],
                        ),
                      ),
                      if (showClose)
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: listBody
                        ? body
                        : WorkoutScrollHint(
                            child: SingleChildScrollView(child: body),
                          ),
                  ),
                ),
                if (actions.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * .42,
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: WorkoutDialogActions(children: actions),
                    ),
                  ),
              ],
            );
          },
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

/// Compact controls stack on phones and share rows on wide displays.
class WorkoutControlGrid extends StatelessWidget {
  const WorkoutControlGrid({
    super.key,
    required this.children,
    this.maxColumns = 2,
  });

  final List<Widget> children;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 8.0;
      const minWidth = 220.0;
      final columns = ((constraints.maxWidth + gap) / (minWidth + gap))
          .floor()
          .clamp(1, maxColumns);
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(valueLabel),
        ],
      ),
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: foreground,
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
