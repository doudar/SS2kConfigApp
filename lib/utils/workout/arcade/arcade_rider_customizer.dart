import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../widgets/workout_dialog.dart';
import 'arcade_rider_appearance.dart';
import 'arcade_rider_art.dart';

class ArcadeRiderCustomizer extends StatefulWidget {
  const ArcadeRiderCustomizer({super.key, required this.initial});
  final ArcadeRiderAppearance initial;

  @override
  State<ArcadeRiderCustomizer> createState() => _ArcadeRiderCustomizerState();
}

class _ArcadeRiderCustomizerState extends State<ArcadeRiderCustomizer> {
  late ArcadeRiderAppearance rider = widget.initial;
  static const skin = [
    ('Porcelain', Color(0xffffdfc4)),
    ('Peach', Color(0xffffc69b)),
    ('Golden', Color(0xffdba16c)),
    ('Warm brown', Color(0xffaf764f)),
    ('Deep brown', Color(0xff794c36)),
    ('Ebony', Color(0xff4b3028)),
  ];
  static const hair = [
    ('Black', Color(0xff252332)),
    ('Brown', Color(0xff583b30)),
    ('Auburn', Color(0xffad5938)),
    ('Blond', Color(0xffe3bd67)),
    ('Silver', Color(0xffd9e3ed)),
    ('Pink', Color(0xffed87c0)),
  ];
  static const kit = [
    ('Mint', Color(0xff74ffd3)),
    ('Sky', Color(0xff67cfff)),
    ('Violet', Color(0xffa78aff)),
    ('Rose', Color(0xffff80ac)),
    ('Red', Color(0xffff6259)),
    ('Orange', Color(0xffffaa58)),
    ('Gold', Color(0xffffd477)),
    ('White', Color(0xfff1f5ff)),
    ('Midnight', Color(0xff252b40)),
    ('Plum', Color(0xff52476e)),
  ];

  Widget colors(
    String title,
    Color selected,
    List<(String, Color)> palette,
    ArcadeRiderAppearance Function(Color) update,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (name, color) in palette)
              Tooltip(
                message: name,
                child: Semantics(
                  label: '$title: $name',
                  button: true,
                  selected: selected == color,
                  child: Material(
                    color: color,
                    shape: CircleBorder(
                      side: BorderSide(
                        color: selected == color
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.outline,
                        width: selected == color ? 3 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => setState(() => rider = update(color)),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: selected == color
                            ? Icon(
                                Icons.check_rounded,
                                color: color.computeLuminance() > .45
                                    ? Colors.black
                                    : Colors.white,
                                size: 20,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => WorkoutDialog(
    title: const Text('Your rider'),
    icon: Icons.checkroom_rounded,
    subtitle: 'Choose your look for Crank Quest.',
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkoutSettingsPanel(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height < 450 ? 100 : 160,
            width: double.infinity,
            child: CustomPaint(painter: _RiderPreview(rider)),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () =>
                setState(() => rider = const ArcadeRiderAppearance()),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset rider appearance'),
          ),
        ),
        colors(
          'Skin',
          rider.skin,
          skin,
          (color) => rider.copyWith(skin: color),
        ),
        colors(
          'Hair',
          rider.hair,
          hair,
          (color) => rider.copyWith(hair: color),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final style in ArcadeHairStyle.values)
              ChoiceChip(
                label: Text(switch (style) {
                  ArcadeHairStyle.short => 'Short',
                  ArcadeHairStyle.curls => 'Curls',
                  ArcadeHairStyle.ponytail => 'Ponytail',
                }),
                selected: rider.hairStyle == style,
                onSelected: (_) =>
                    setState(() => rider = rider.copyWith(hairStyle: style)),
              ),
          ],
        ),
        const SizedBox(height: 18),
        colors(
          'Jersey',
          rider.jersey,
          kit,
          (color) => rider.copyWith(jersey: color),
        ),
        colors(
          'Shorts',
          rider.shorts,
          kit,
          (color) => rider.copyWith(shorts: color),
        ),
        colors(
          'Helmet',
          rider.helmet,
          kit,
          (color) => rider.copyWith(helmet: color),
        ),
        colors('Bike', rider.bike, kit, (color) => rider.copyWith(bike: color)),
        colors(
          'Shoes & gloves',
          rider.shoes,
          kit,
          (color) => rider.copyWith(shoes: color),
        ),
      ],
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: () => Navigator.of(context).pop(rider),
        icon: const Icon(Icons.check_rounded),
        label: const Text('Apply look'),
      ),
    ],
  );
}

class _RiderPreview extends CustomPainter {
  const _RiderPreview(this.rider);
  final ArcadeRiderAppearance rider;

  @override
  void paint(Canvas c, Size size) {
    final scale = math.min(size.width / 150, size.height / 115);
    c.save();
    c.translate(size.width / 2, size.height * .81);
    c.scale(scale);
    c.drawOval(
      const Rect.fromLTWH(-53, 9, 112, 17),
      Paint()..color = rider.bike.withValues(alpha: .10),
    );
    ArcadeRiderArt.paint(c, Offset.zero, rider: rider, pedalPhase: .8);
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _RiderPreview oldDelegate) =>
      oldDelegate.rider != rider;
}
