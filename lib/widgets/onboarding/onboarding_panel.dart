import 'dart:ui';

import 'package:flutter/material.dart';

class OnboardingStyle {
  final ThemeData theme;

  const OnboardingStyle._(this.theme);

  factory OnboardingStyle.of(BuildContext context) {
    return OnboardingStyle._(Theme.of(context));
  }

  bool get isLight => theme.brightness == Brightness.light;
  ColorScheme get colorScheme => theme.colorScheme;
  Color get accent => Colors.red;
  Color get accentStrong => isLight ? Colors.red.shade700 : Colors.redAccent;
  Color get foreground => isLight ? colorScheme.onSurface : Colors.white;
  Color get body => foreground.withValues(alpha: isLight ? 0.82 : 0.86);
  Color get muted => foreground.withValues(alpha: isLight ? 0.62 : 0.74);
  Color get scaffoldBackground =>
      isLight ? colorScheme.surface : Colors.black;
  Color get bottomBarBackground =>
      isLight ? colorScheme.surface : Colors.black;
  Color get imageBackground => isLight
      ? Color.alphaBlend(
          Colors.red.withValues(alpha: 0.04),
          colorScheme.surfaceContainerHighest,
        )
      : Color.alphaBlend(
          Colors.red.withValues(alpha: 0.08),
          Colors.black.withValues(alpha: 0.72),
        );
  Color get imageBorder =>
      Colors.red.withValues(alpha: isLight ? 0.16 : 0.24);
  Color get placeholderBackground => isLight
      ? colorScheme.surfaceContainerHighest
      : Colors.black.withValues(alpha: 0.52);

  LinearGradient get appBarGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isLight
            ? [
                Colors.white,
                const Color(0xFFFFECEC),
              ]
            : [
                Colors.black.withValues(alpha: 0.92),
                Colors.red.withValues(alpha: 0.80),
              ],
      );

  LinearGradient get scaffoldGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isLight
            ? [
                colorScheme.surface,
                const Color(0xFFFFF8F8),
                colorScheme.surface,
              ]
            : [
                Colors.black,
                const Color(0xFF170505),
                Colors.black.withValues(alpha: 0.98),
              ],
      );

  LinearGradient get panelGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isLight
            ? [
                Colors.white,
                const Color(0xFFFFF8F8),
                const Color(0xFFFFEFEF),
              ]
            : [
                Colors.red.withValues(alpha: 0.78),
                Colors.black.withValues(alpha: 0.94),
                const Color(0xFF1A0606).withValues(alpha: 0.90),
              ],
        stops: const [0.0, 0.60, 1.0],
      );

  LinearGradient buttonGradient(bool enabled) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: enabled
            ? isLight
                ? [
                    Colors.red.shade700,
                    Colors.red.shade800,
                  ]
                : const [
                    Color(0xFF1B1B1B),
                    Color(0xFF2A2A2A),
                  ]
            : isLight
                ? [
                    colorScheme.surfaceContainerHighest,
                    colorScheme.surfaceContainerHighest,
                  ]
                : [
                    Colors.black.withValues(alpha: 0.30),
                    Colors.black.withValues(alpha: 0.18),
                  ],
      );

  Color selectableBackground(bool selected) {
    if (isLight) {
      return selected
          ? Color.alphaBlend(
              Colors.red.withValues(alpha: 0.08),
              colorScheme.surface,
            )
          : colorScheme.surface;
    }
    return selected
        ? const Color(0xFF3A0D0D).withValues(alpha: 0.92)
        : const Color.fromARGB(255, 54, 27, 26).withValues(alpha: 0.24);
  }
}

class OnboardingPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const OnboardingPanel({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  }) : super(key: key);

  static const double radius = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = OnboardingStyle.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: style.panelGradient,
            border: Border.all(
              color: Colors.red.withValues(alpha: style.isLight ? 0.24 : 0.45),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black.withValues(alpha: style.isLight ? 0.12 : 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: theme.textTheme.bodyMedium?.copyWith(
                  color: style.body,
                ) ??
                TextStyle(color: style.body),
            child: IconTheme(
              data: IconThemeData(color: style.foreground),
              child: Padding(
                padding: padding,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingSelectableCard extends StatelessWidget {
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const OnboardingSelectableCard({
    Key? key,
    required this.selected,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = OnboardingStyle.of(context);
    final backgroundColor = style.selectableBackground(selected);

    return Card(
      elevation: selected ? 3 : 0,
      shadowColor: Colors.black.withValues(alpha: style.isLight ? 0.10 : 0.28),
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OnboardingPanel.radius),
        side: BorderSide(
          color: selected
              ? Colors.red.withValues(alpha: style.isLight ? 0.46 : 0.72)
              : style.isLight
                  ? style.colorScheme.outlineVariant.withValues(alpha: 0.70)
                  : const Color.fromARGB(255, 66, 26, 23)
                      .withValues(alpha: 0.42),
          width: selected ? 1.4 : 1,
        ),
      ),
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(OnboardingPanel.radius),
        splashColor: Colors.red.withValues(alpha: 0.18),
        highlightColor: Colors.red.withValues(alpha: 0.08),
        onTap: onTap,
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium?.copyWith(
                color: style.body,
              ) ??
              TextStyle(color: style.body),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class OnboardingRadioCard<T> extends StatelessWidget {
  final T value;
  final String title;
  final String subtitle;
  final bool selected;

  const OnboardingRadioCard({
    Key? key,
    required this.value,
    required this.title,
    required this.subtitle,
    required this.selected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = OnboardingStyle.of(context);

    return OnboardingSelectableCard(
      selected: selected,
      padding: EdgeInsets.zero,
      child: RadioListTile<T>(
        value: value,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OnboardingPanel.radius),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: style.foreground,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: style.body,
              height: 1.35,
            ),
          ),
        ),
        activeColor: style.accentStrong,
      ),
    );
  }
}

class OnboardingOptionCard extends StatelessWidget {
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;
  final String? metadata;
  final bool recommended;
  final Widget? trailing;

  const OnboardingOptionCard({
    Key? key,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.metadata,
    this.recommended = false,
    this.trailing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = OnboardingStyle.of(context);

    return OnboardingSelectableCard(
      selected: selected,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: selected ? style.accentStrong : style.muted,
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
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: style.foreground,
                      ),
                    ),
                    if (metadata != null)
                      Text(
                        metadata!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: style.muted,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (recommended) const _RecommendedBadge(),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: style.body,
                    height: 1.4,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(height: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingBadge extends StatelessWidget {
  final Widget child;

  const OnboardingBadge({
    Key? key,
    required this.child,
  }) : super(key: key);

  factory OnboardingBadge.number(int number) {
    return OnboardingBadge(child: Text('$number'));
  }

  factory OnboardingBadge.icon(IconData icon) {
    return OnboardingBadge(child: Icon(icon, size: 24));
  }

  @override
  Widget build(BuildContext context) {
    final style = OnboardingStyle.of(context);

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: style.isLight
            ? Colors.red.withValues(alpha: 0.08)
            : const Color.fromARGB(255, 54, 27, 26).withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(OnboardingPanel.radius),
        border: Border.all(
          color: Colors.red.withValues(alpha: 0.45),
        ),
      ),
      child: Center(
        child: DefaultTextStyle(
          style: TextStyle(
            color: style.isLight ? style.accentStrong : Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 17,
            height: 1.0,
          ),
          child: IconTheme(
            data: IconThemeData(color: style.accentStrong),
            child: child,
          ),
        ),
      ),
    );
  }
}

class OnboardingChecklistItem extends StatelessWidget {
  final String text;

  const OnboardingChecklistItem(
    this.text, {
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final style = OnboardingStyle.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle,
            size: 20,
            color: style.accentStrong,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: style.body,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingCallout extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? color;

  const OnboardingCallout({
    Key? key,
    required this.text,
    this.icon = Icons.info_outline,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final style = OnboardingStyle.of(context);
    final accent = color ?? style.accentStrong;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: style.isLight
            ? Colors.red.withValues(alpha: 0.05)
            : const Color.fromARGB(255, 54, 27, 26).withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(OnboardingPanel.radius),
        border: Border.all(color: accent.withValues(alpha: 0.42)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: style.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge();

  @override
  Widget build(BuildContext context) {
    final style = OnboardingStyle.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: style.isLight ? 0.10 : 0.22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Recommended',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: style.accentStrong,
        ),
      ),
    );
  }
}
