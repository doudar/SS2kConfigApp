import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'workout_parser.dart';
import 'workout_tts_settings.dart';
import 'workout_controller.dart';
import 'workout_constants.dart';

// Keys for SharedPreferences
const String _textSizeKey = 'workout_text_size';
const String _scrollSpeedKey = 'workout_scroll_speed';
const double _scrollOvershootScreens = 1.25; // extra screen widths to travel past the left edge

class WorkoutTextEventOverlay extends StatefulWidget {
  static Future<void> saveTextSettings(double textSize, double scrollSpeed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_textSizeKey, textSize);
    await prefs.setDouble(_scrollSpeedKey, scrollSpeed);
  }

  static Future<Map<String, double>> loadTextSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'textSize': prefs.getDouble(_textSizeKey) ?? WorkoutTextStyle.scrollingText,
      'scrollSpeed': prefs.getDouble(_scrollSpeedKey) ?? WorkoutTextStyle.scrollSpeed,
    };
  }
  final WorkoutSegment? currentSegment;
  final int secondsIntoSegment;
  final WorkoutTTSSettings ttsSettings;
  final WorkoutController workoutController;

  final String? testText;

  const WorkoutTextEventOverlay({
    Key? key,
    required this.currentSegment,
    required this.secondsIntoSegment,
    required this.ttsSettings,
    required this.workoutController,
    this.testText,
  }) : super(key: key);

  @override
  State<WorkoutTextEventOverlay> createState() => _WorkoutTextEventOverlayState();
}

class _WorkoutTextEventOverlayState extends State<WorkoutTextEventOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _scrollController;
  late Animation<double> _pixelAnimation;

  String? _currentEventSignature;
  double? _lastScreenWidth;
  double? _lastTextWidth;

  static const double _edgePadding = 24.0; // extra padding to ensure text starts fully off-screen

  @override
  void initState() {
    super.initState();
    
    // Load saved text settings
    WorkoutTextEventOverlay.loadTextSettings().then((settings) {
      WorkoutTextStyle.scrollingText = settings['textSize']!;
      WorkoutTextStyle.scrollSpeed = settings['scrollSpeed']!;
    });
    _scrollController = AnimationController(vsync: this);
    _pixelAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(_scrollController);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _resetAnimationState() {
    _currentEventSignature = null;
    _lastScreenWidth = null;
    _lastTextWidth = null;
    _scrollController.stop();
  }

  double _measureTextWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();

    return painter.width;
  }

  void _startScrollAnimation({
    required String signature,
    required double screenWidth,
    required double textWidth,
  }) {
    final safeTextWidth = textWidth <= 0 ? 1.0 : textWidth;
    final startX = screenWidth + _edgePadding;
    final endX = -(safeTextWidth + _edgePadding + (screenWidth * _scrollOvershootScreens));
    final travelDistance = startX - endX;
    final pixelsPerSecond = WorkoutTextStyle.scrollSpeed <= 0 ? 1.0 : WorkoutTextStyle.scrollSpeed;
    final durationMs = (travelDistance / pixelsPerSecond * 1000).clamp(100.0, 600000.0).round();

    _pixelAnimation = Tween<double>(begin: startX, end: endX).animate(
      CurvedAnimation(parent: _scrollController, curve: Curves.linear),
    );

    _scrollController.duration = Duration(milliseconds: durationMs);
    _scrollController.reset();
    _scrollController.forward();

    _currentEventSignature = signature;
    _lastScreenWidth = screenWidth;
    _lastTextWidth = safeTextWidth;
  }

  void _maybeStartScrollAnimation({
    required String signature,
    required double screenWidth,
    required double textWidth,
  }) {
    final widthChanged = _lastScreenWidth == null || (screenWidth - _lastScreenWidth!).abs() > 1.0;
    final textChanged = _lastTextWidth == null || (textWidth - _lastTextWidth!).abs() > 1.0;
    final hasNewEvent = _currentEventSignature != signature;

    if (hasNewEvent || widthChanged || textChanged) {
      _startScrollAnimation(
        signature: signature,
        screenWidth: screenWidth,
        textWidth: textWidth,
      );
    }
  }

  @override
  void didUpdateWidget(WorkoutTextEventOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Clear spoken messages and animated events when segment changes
    if (widget.currentSegment != oldWidget.currentSegment) {
      widget.ttsSettings.clearSpokenMessages();
      _resetAnimationState();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentSegment == null) return const SizedBox.shrink();

    // Only show the most recent text event from the current segment
    final currentEvents = widget.currentSegment!.textEvents
        .where((event) => event.timeOffset <= widget.secondsIntoSegment)
        .toList();
    
    if (currentEvents.isEmpty) return const SizedBox.shrink();

    // Get the most recent event
    final latestEvent = currentEvents.last;
    final message = widget.testText ?? latestEvent.message;

    // Speak only the latest message if it hasn't been spoken yet
    widget.ttsSettings.speak(message);

    final textStyle = TextStyle(
      fontSize: WorkoutTextStyle.scrollingText,
      fontWeight: FontWeight.bold,
      shadows: [
        Shadow(
          blurRadius: 3.0,
          color: const Color.fromARGB(255, 48, 47, 47).withValues(alpha: 0.75),
          offset: const Offset(1.0, 1.0),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final textWidth = _measureTextWidth(message, textStyle);
        final signature = '${widget.currentSegment.hashCode}-${latestEvent.timeOffset}-$message';

        _maybeStartScrollAnimation(
          signature: signature,
          screenWidth: screenWidth,
          textWidth: textWidth,
        );

        return SizedBox(
          width: screenWidth,
          child: AnimatedBuilder(
            animation: _pixelAnimation,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(_pixelAnimation.value, 0),
                child: child,
              );
            },
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                message,
                style: textStyle,
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
            ),
          ),
        );
      },
    );
  }
}
