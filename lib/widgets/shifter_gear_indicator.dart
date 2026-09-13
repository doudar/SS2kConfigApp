import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Displays the current virtual gear with a short rolling transition when it
/// changes.
///
/// The transition keeps the indicator's box at a stable size, so the shift
/// controls around it do not move while the device confirms a new gear. The
/// [shifting] state adds a small amount of scale and blur while that
/// confirmation is pending.
class ShifterGearIndicator extends StatefulWidget {
  const ShifterGearIndicator({
    super.key,
    required this.value,
    required this.shifting,
    required this.color,
  });

  final String value;
  final bool shifting;
  final Color color;

  @override
  State<ShifterGearIndicator> createState() => _ShifterGearIndicatorState();
}

class _ShifterGearIndicatorState extends State<ShifterGearIndicator>
    with TickerProviderStateMixin {
  static const _rollDuration = Duration(milliseconds: 420);
  static const _effectDuration = Duration(milliseconds: 180);
  static const _fontSize = 72.0;
  static const _lineHeight = 1.15;

  late final AnimationController _rollController;
  late final AnimationController _effectController;
  late final Listenable _animations;

  String? _fromValue;
  int _rollDirection = 1;
  bool? _animationsDisabled;

  @override
  void initState() {
    super.initState();
    _rollController = AnimationController(
      vsync: this,
      duration: _rollDuration,
      value: 1,
    )..addStatusListener(_handleRollStatus);
    _effectController = AnimationController(
      vsync: this,
      duration: _effectDuration,
    );
    _animations = Listenable.merge([_rollController, _effectController]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (_animationsDisabled == disabled) return;
    _animationsDisabled = disabled;
    if (disabled) {
      _rollController.value = 1;
      _fromValue = null;
      _effectController.value = 0;
    } else {
      _syncShiftEffect();
    }
  }

  @override
  void didUpdateWidget(covariant ShifterGearIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.value != widget.value) {
      _fromValue = oldWidget.value;
      _rollDirection = _directionFor(oldWidget.value, widget.value);
      if (_animationsDisabled ?? false) {
        _rollController.value = 1;
        _fromValue = null;
      } else {
        _rollController.forward(from: 0);
      }
    }

    if (oldWidget.shifting != widget.shifting) _syncShiftEffect();
  }

  int _directionFor(String oldValue, String newValue) {
    final oldNumber = int.tryParse(oldValue);
    final newNumber = int.tryParse(newValue);
    if (oldNumber != null && newNumber != null && newNumber < oldNumber) {
      return -1;
    }
    return 1;
  }

  void _syncShiftEffect() {
    final disabled = _animationsDisabled ?? false;
    final target = widget.shifting && !disabled ? 1.0 : 0.0;
    if (disabled) {
      _effectController.value = target;
    } else {
      _effectController.animateTo(target, curve: Curves.easeOutCubic);
    }
  }

  void _handleRollStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    if (_fromValue != null) setState(() => _fromValue = null);
  }

  @override
  void dispose() {
    _rollController.dispose();
    _effectController.dispose();
    super.dispose();
  }

  Text _text(String value, double fontSize) => Text(
    value,
    maxLines: 1,
    // _rollingText applies the ambient text scale to the font size before
    // constructing this Text. Do not let Text apply the same scale again.
    textScaler: TextScaler.noScaling,
    style: TextStyle(
      color: widget.color,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      height: _lineHeight,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  Widget _centeredText(String value, double fontSize) =>
      Align(alignment: Alignment.center, child: _text(value, fontSize));

  Widget _rollingText(BuildContext context, double progress) {
    final textScaler = MediaQuery.textScalerOf(context);
    final fontSize = textScaler.scale(_fontSize);
    final height = fontSize * _lineHeight;
    final fromValue = _fromValue;
    final reducedMotion = _animationsDisabled ?? false;
    final rolling = fromValue != null && progress < 1 && !reducedMotion;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: ClipRect(
        child: rolling
            ? Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  FractionalTranslation(
                    translation: Offset(0, -_rollDirection * progress),
                    child: Opacity(
                      opacity: 1 - progress,
                      child: _centeredText(fromValue, fontSize),
                    ),
                  ),
                  FractionalTranslation(
                    translation: Offset(0, _rollDirection * (1 - progress)),
                    child: Opacity(
                      opacity: progress,
                      child: _centeredText(widget.value, fontSize),
                    ),
                  ),
                ],
              )
            : _centeredText(widget.value, fontSize),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = _animationsDisabled ?? false;

    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Virtual gear',
      value: widget.value,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _animations,
          builder: (context, _) {
            final progress = reducedMotion ? 1.0 : _rollController.value;
            final effect = reducedMotion ? 0.0 : _effectController.value;
            final scale = 1.0 + effect * .018;
            final blur = effect * .55;
            Widget child = _rollingText(context, progress);
            if (blur > 0) {
              child = ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: child,
              );
            }
            return Transform.scale(scale: scale, child: child);
          },
        ),
      ),
    );
  }
}
