import 'package:flutter/material.dart';

/// A touch-friendly cue for the nearest vertical viewport. Nested viewports
/// have their own cue, so reaching one list's end cannot hide another's hint.
class WorkoutScrollHint extends StatefulWidget {
  const WorkoutScrollHint({super.key, required this.child});

  final Widget child;

  @override
  State<WorkoutScrollHint> createState() => _WorkoutScrollHintState();
}

class _WorkoutScrollHintState extends State<WorkoutScrollHint> {
  bool _showHint = false;
  bool _nextShowHint = false;
  bool _updateScheduled = false;

  void _update(ScrollMetrics metrics, int depth) {
    if (depth != 0 || metrics.axis != Axis.vertical) return;
    _nextShowHint = switch (metrics.axisDirection) {
      AxisDirection.down => metrics.extentAfter > 1,
      AxisDirection.up => metrics.extentBefore > 1,
      _ => false,
    };
    if (_updateScheduled) return;
    _updateScheduled = true;
    // Metrics notifications can arrive during layout, including when content
    // loads asynchronously or the keyboard changes the available height.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (mounted && _showHint != _nextShowHint) {
        setState(() => _showHint = _nextShowHint);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        _update(notification.metrics, notification.depth);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _update(notification.metrics, notification.depth);
          return false;
        },
        child: Stack(
          children: [
            widget.child,
            if (_showHint)
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: IgnorePointer(
                  child: Center(
                    child: Semantics(
                      label: 'More content below. Swipe up to scroll.',
                      child: Material(
                        color: colors.surface,
                        elevation: 3,
                        shape: StadiumBorder(
                          side: BorderSide(
                            color: colors.outline.withValues(alpha: .25),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 28,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
