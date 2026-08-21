import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Returns the graph width for the current visible workout window.
///
/// Short workouts still occupy the full viewport so overlays positioned beside
/// the graph retain their intended screen-relative placement.
double calculateWorkoutGraphWidth({
  required double viewportWidth,
  required double workoutDurationSeconds,
  required double visibleMinutes,
}) {
  final scaledWidth =
      workoutDurationSeconds / 60 * (viewportWidth / visibleMinutes);
  return math.max(viewportWidth, scaledWidth);
}

/// Base size constant that controls the overall scale of metric boxes
class WorkoutMetricScale {
  /// Base size that all metric box measurements are derived from
  static const double baseSize = 60.0; // Current height of metric box
}

/// Padding and spacing constants used throughout the workout UI
class WorkoutPadding {
  /// Standard edge padding for cards and containers
  static const double standard = 8.0;

  /// Small padding for tight spaces
  static const double small = 6.0;

  /// Horizontal padding for metric boxes (5% of base size)
  static const double metricHorizontal = WorkoutMetricScale.baseSize * 0.05;

  /// Internal padding for metric box content (25% of base size)
  static const double metricBoxContent = WorkoutMetricScale.baseSize * 0.25;
}

/// Vertical spacing constants
class WorkoutSpacing {
  /// Extra extra small vertical spacing
  static const double xxsmall = 4.0;

  /// Extra small vertical spacing
  static const double xsmall = 8.0;

  /// Small vertical spacing
  static const double small = 16.0;

  /// Medium vertical spacing
  static const double medium = 20.0;

  /// Spacing between metric label and value (5% of base size)
  static const double metricLabelValue = WorkoutMetricScale.baseSize * 0.05;

  /// Spacing between value and unit (2.5% of base size)
  static const double metricValueUnit = WorkoutMetricScale.baseSize * 0.025;
}

/// Size constants for various UI elements
class WorkoutSizes {
  /// Width of the FTP input field
  static const double ftpFieldWidth = 80.0;

  /// Width of the progress indicator line
  static const double progressIndicatorWidth = 3.0;

  /// Height of the cadence indicator
  static const double cadenceIndicatorHeight = 20.0;

  /// Radius of the actual power dot
  static const double actualPowerDotRadius = 2.0;

  /// Minimum width for metric boxes (1.25x base size)
  static const double metricBoxMinWidth = WorkoutMetricScale.baseSize * 1.25;

  /// Maximum width for metric boxes (2x base size)
  static const double metricBoxMaxWidth = WorkoutMetricScale.baseSize * 2.0;

  /// Height for metric boxes (same as base size)
  static const double metricBoxHeight = WorkoutMetricScale.baseSize;

  /// Border radius for metric boxes (15% of base size)
  static const double metricBoxBorderRadius = WorkoutMetricScale.baseSize * 0.15;

  /// Character width multiplier for metric value sizing (25% of base size)
  static const double metricCharacterWidth = WorkoutMetricScale.baseSize * 0.25;
}

/// Font size constants
class WorkoutFontSizes {
  /// Font size for grid labels and small text
  static const double small = 12.0;

  /// Base font size for metric values (35% of base size)
  static const double metricValueBase = WorkoutMetricScale.baseSize * 0.35;

  /// Minimum font size for metric values (20% of base size)
  static const double metricValueMin = WorkoutMetricScale.baseSize * 0.20;

  /// Font size for metric labels (17.5% of base size)
  static const double metricLabel = WorkoutMetricScale.baseSize * 0.175;

  /// Font size for metric units (15% of base size)
  static const double metricUnit = WorkoutMetricScale.baseSize * 0.15;
}

/// Font weight constants
class WorkoutFontWeights {
  /// Font weight for metric labels
  static const FontWeight metricLabel = FontWeight.w500;

  /// Font weight for metric values
  static const FontWeight metricValue = FontWeight.bold;
}

/// Shadow constants for various UI elements
class WorkoutShadows {
  /// Shadow for metric boxes
  static final BoxShadow metricBox = BoxShadow(
    color: Colors.black.withValues(alpha: 0.1),
    blurRadius: WorkoutMetricScale.baseSize * 0.05, // 5% of base size
    offset: Offset(0, WorkoutMetricScale.baseSize * 0.025), // 2.5% of base size
  );
}

/// Duration constants for animations and intervals
class WorkoutDurations {
  /// Interval for progress updates
  static const Duration progressUpdateInterval = Duration(milliseconds: 100);
  /// Length (in minutes) of the full workout shown in "preview" (zoomed-out) mode.
  /// This value is updated dynamically to match the currently loaded workout
  /// total duration. Default fallback is 90 minutes until a workout loads.
  static double previewMinutes = 90.0;
  ///Length of workout playing window
  static const double playingMinutes = 10;
}

/// Text style constants for workout text overlay
class WorkoutTextStyle {
  /// Font size for scrolling workout text
  static double scrollingText = 48.0;
  /// Speed of text scrolling in pixels per second
  static double scrollSpeed = 150.0;
}

/// Grid constants for the workout graph
class WorkoutGrid {
  /// Interval for power grid lines (in watts)
  static const double powerLineInterval = 100.0;

  /// Interval for time grid lines (in seconds)
  static const double timeLineInterval = 300.0; // 5 minutes
}

/// Opacity values for various UI elements
class WorkoutOpacity {
  /// Opacity for segment colors
  static const double segmentColor = 0.7;

  /// Opacity for grid lines
  static const double gridLines = 0.5;

  /// Opacity for segment borders
  static const double segmentBorder = 0.1;

  /// Opacity for actual power line
  static const double actualPowerLine = 0.8;
}

/// Stroke width constants for lines and borders
class WorkoutStroke {
  /// Width for standard borders
  static const double border = 1.0;

  /// Width for cadence indicator
  static const double cadenceIndicator = 2.0;

  /// Width for actual power line
  static const double actualPowerLine = 1.5;
}

/// FTP percentage zones for power-based coloring
class WorkoutZones {
  /// Recovery zone (< 55% FTP)
  static const double recovery = 0.55;

  /// Endurance zone (55-75% FTP)
  static const double endurance = 0.75;

  /// Tempo zone (76-87% FTP)
  static const double tempo = 0.87;

  /// Threshold zone (88-95% FTP)
  static const double threshold = 0.95;

  /// VO2Max zone (96-105% FTP)
  static const double vo2max = 1.05;

  /// Anaerobic zone (106-120% FTP)
  static const double anaerobic = 1.20;

  /// Neuromuscular zone (> 120% FTP)
  static const double neuromuscular = 1.50;
}

// Default cooldown values (70% to 50% FTP)
const double defaultCooldownStart = 0.70;
const double defaultCooldownEnd = 0.50;
