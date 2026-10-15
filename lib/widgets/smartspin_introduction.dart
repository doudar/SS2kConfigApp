import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shared by first-run setup and device discovery. All artwork is bundled.
class SmartSpinIntroduction extends StatelessWidget {
  const SmartSpinIntroduction({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    final foreground = light ? const Color(0xFF241C20) : Colors.white;
    final secondary = light ? const Color(0xFF5A4B50) : const Color(0xFFD8CDD0);
    final accent = light ? const Color(0xFFB32635) : const Color(0xFFFF9A9E);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light
              ? const [Color(0xFFFFF1EF), Color(0xFFFFFFFF)]
              : const [Color(0xFF351A23), Color(0xFF17171E)],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MEET SMARTSPIN2K',
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final copy = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Your spin bike.\nA smarter ride.',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'SmartSpin2k is a physical add-on that turns your bike’s '
                      'resistance knob for you. Focus on the ride while it '
                      'adjusts the effort.',
                      style: TextStyle(
                        color: secondary,
                        fontSize: 16,
                        height: 1.45,
                      ),
                    ),
                  ],
                );
                final product = Semantics(
                  image: true,
                  label: 'SmartSpin2k hardware with its resistance knob mount',
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0xFFF2D8D5), Color(0xFFE9BDB9)],
                        ),
                      ),
                      child: Image.asset(
                        'assets/ss2kv3.png',
                        height: 150,
                        width: 150,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                );
                if (constraints.maxWidth >= 580) {
                  return Row(
                    children: [
                      Expanded(child: copy),
                      const SizedBox(width: 24),
                      product,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    copy,
                    const SizedBox(height: 20),
                    Center(child: product),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: light ? Colors.white : const Color(0xFF24232B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hardware required',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'The app sets up and controls your SmartSpin2k. '
                    'Installing the app alone does not control bike resistance.',
                    style: TextStyle(color: secondary, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _Benefit(
              icon: Icons.landscape_outlined,
              title: 'Feel the hills',
              detail:
                  'Resistance follows the terrain in compatible training apps.',
              foreground: foreground,
              secondary: secondary,
              accent: accent,
            ),
            const SizedBox(height: 16),
            _Benefit(
              icon: Icons.bolt_outlined,
              title: 'Stay on target',
              detail:
                  'ERG mode adjusts resistance to your workout’s power target.',
              foreground: foreground,
              secondary: secondary,
              accent: accent,
            ),
            const SizedBox(height: 16),
            _Benefit(
              icon: Icons.swap_vert_rounded,
              title: 'Shift your way',
              detail:
                  'Change effort with virtual shifting instead of reaching for the knob.',
              foreground: foreground,
              secondary: secondary,
              accent: accent,
            ),
            const SizedBox(height: 24),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () =>
                  openSmartSpinLink(context, 'https://smartspin2k.com/'),
              style: TextButton.styleFrom(
                foregroundColor: accent,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Explore hardware & bike compatibility'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.detail,
    required this.foreground,
    required this.secondary,
    required this.accent,
  });
  final IconData icon;
  final String title;
  final String detail;
  final Color foreground;
  final Color secondary;
  final Color accent;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(child: Icon(icon, color: accent, size: 24)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: foreground,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(detail, style: TextStyle(color: secondary, height: 1.4)),
          ],
        ),
      ),
    ],
  );
}

Future<void> openSmartSpinLink(BuildContext context, String url) async {
  try {
    if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      return;
    }
  } catch (_) {
    // Keep setup available when offline or no browser can handle the link.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Unable to open $url. Please try again later.')),
    );
  }
}
