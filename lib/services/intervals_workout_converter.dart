
class IntervalsWorkoutConverter {
  /// Converts an Intervals.icu workout document to ZWO format for the workout controller
  static String convertToZwo(Map<String, dynamic> workoutDoc) {
    final workoutFile = workoutDoc['workout_file'];
    
    if (workoutFile is String) {
      // If it's already a ZWO file, return as-is
      if (workoutFile.trim().startsWith('<')) {
        return workoutFile;
      }
    }
    
    // If it's structured data, convert to ZWO format
    final description = workoutDoc['description'] ?? '';
    final name = workoutDoc['name'] ?? 'Intervals.icu Workout';
    final steps = workoutDoc['steps'] ?? [];
    
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<workout_file>');
    buffer.writeln('  <author>Intervals.icu</author>');
    buffer.writeln('  <name>$name</name>');
    buffer.writeln('  <description>$description</description>');
    buffer.writeln('  <sportType>bike</sportType>');
    buffer.writeln('  <tags/>');
    buffer.writeln('  <workout>');
    
    // Convert steps to ZWO segments
    for (final step in steps) {
      if (step is Map<String, dynamic>) {
        _convertStepToZwo(buffer, step);
      }
    }
    
    buffer.writeln('  </workout>');
    buffer.writeln('</workout_file>');
    
    return buffer.toString();
  }
  
  static void _convertStepToZwo(StringBuffer buffer, Map<String, dynamic> step) {
    final duration = step['duration'] ?? 0;
    final powerLow = step['power_low'] ?? step['power'] ?? 0;
    final powerHigh = step['power_high'] ?? powerLow;
    final cadence = step['cadence'];
    
    // Determine if this is a ramp (power changes) or steady
    if (powerLow != powerHigh) {
      // Ramp segment
      buffer.writeln('    <Ramp Duration="$duration" PowerLow="${powerLow / 100.0}" PowerHigh="${powerHigh / 100.0}"/>');
    } else {
      // Steady segment
      buffer.writeln('    <SteadyState Duration="$duration" Power="${powerLow / 100.0}"${cadence != null ? ' Cadence="$cadence"' : ''}/>');
    }
  }
  
  /// Extracts basic workout info from Intervals.icu event
  static Map<String, dynamic> extractWorkoutInfo(Map<String, dynamic> event) {
    return {
      'name': event['name'] ?? 'Intervals.icu Workout',
      'description': event['description'] ?? '',
      'duration': event['planned_duration'] ?? 0,
      'tss': event['planned_tss'] ?? 0,
      'if': event['planned_if'] ?? 0,
    };
  }
}