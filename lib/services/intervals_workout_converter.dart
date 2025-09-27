
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
    
    // Convert (possibly nested) steps to ZWO segments
    _emitSteps(buffer, steps);
    
    buffer.writeln('  </workout>');
    buffer.writeln('</workout_file>');
    
    return buffer.toString();
  }
  
  static void _emitSteps(StringBuffer buffer, dynamic steps) {
    if (steps is! List) return;
    for (final raw in steps) {
      if (raw is! Map) continue;
      final step = Map<String, dynamic>.from(raw as Map);

      // Nested group with its own steps (optionally with repeat count). Intervals may use
      // keys: reps, repeat, repeats, count. The screenshot shows 'reps'.
      if (step['steps'] is List && (step['duration'] == null || step['power'] == null)) {
        final repeat = _toNum(step['reps'] ?? step['repeat'] ?? step['repeats'] ?? step['count']);
        final reps = repeat != null && repeat > 0 ? repeat.toInt() : 1;
        for (var i = 0; i < reps; i++) {
          _emitSteps(buffer, step['steps']);
        }
        continue;
      }

      _convertSingleStep(buffer, step);
    }
  }

  static num? _toNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  static void _convertSingleStep(StringBuffer buffer, Map<String, dynamic> step) {
    final duration = _toNum(step['duration'] ?? step['length']) ?? 0; // seconds

    // Intervals.icu step may have a nested 'power' map or explicit values.
    num? start;
    num? end;
    num? value;
    String? units;

    final power = step['power'];
    if (power is Map) {
      final pMap = power as Map;
      start = _toNum(pMap['start'] ?? pMap['low']);
      end = _toNum(pMap['end'] ?? pMap['high']);
      value = _toNum(pMap['value'] ?? pMap['target']);
      units = pMap['units']?.toString();
    } else if (power is num || power is String) {
      value = _toNum(power);
    }

    // Legacy fields fallback
    start ??= _toNum(step['power_low']);
    end ??= _toNum(step['power_high']);
    value ??= _toNum(step['power']);

    if (value == null && start != null && end == null) value = start; // treat single value as steady

    double scale(num v) {
      if (units == null || units == '%ftp' || units.toLowerCase().contains('%ftp')) {
        return v / 100.0; // convert %ftp to fraction
      }
      return v.toDouble();
    }

    final cadence = _toNum(step['cadence']);

    if (start != null && end != null && start != end) {
      buffer.writeln('    <Ramp Duration="$duration" PowerLow="${scale(start)}" PowerHigh="${scale(end)}"${cadence != null ? ' Cadence="${cadence.toInt()}"' : ''}/>' );
    } else {
      final steadyVal = value ?? start ?? end ?? 0;
      buffer.writeln('    <SteadyState Duration="$duration" Power="${scale(steadyVal)}"${cadence != null ? ' Cadence="${cadence.toInt()}"' : ''}/>' );
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