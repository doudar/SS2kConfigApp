
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
    
    // Track cumulative time for global textevents (if needed)
    final _TextEventCollector textCollector = _TextEventCollector();
    _emitSteps(buffer, steps, textCollector: textCollector);
    
    buffer.writeln('  </workout>');
    // Optionally emit a global textevents block if any collected
    if (textCollector.events.isNotEmpty) {
      buffer.writeln('  <textevents>');
      for (final e in textCollector.events) {
        // timeoffset is absolute from workout start
        buffer.writeln('    <textevent timeoffset="${e.timeOffset}" message="${_escapeXml(e.message)}" duration="${e.duration}"/>');
      }
      buffer.writeln('  </textevents>');
    }
    buffer.writeln('</workout_file>');
    
    return buffer.toString();
  }
  
  static void _emitSteps(StringBuffer buffer, dynamic steps, {required _TextEventCollector textCollector}) {
    if (steps is! List) return;
    for (final raw in steps) {
      if (raw is! Map) continue;
      final step = Map<String, dynamic>.from(raw);

      // Nested group with its own steps (optionally with repeat count). Intervals may use
      // keys: reps, repeat, repeats, count. The screenshot shows 'reps'.
      if (step['steps'] is List && (step['duration'] == null || step['power'] == null)) {
        final repeat = _toNum(step['reps'] ?? step['repeat'] ?? step['repeats'] ?? step['count']);
        final reps = repeat != null && repeat > 0 ? repeat.toInt() : 1;
        for (var i = 0; i < reps; i++) {
          _emitSteps(buffer, step['steps'], textCollector: textCollector);
        }
        continue;
      }
      _convertSingleStep(buffer, step, textCollector: textCollector);
    }
  }

  static num? _toNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  static void _convertSingleStep(StringBuffer buffer, Map<String, dynamic> step, {required _TextEventCollector textCollector}) {
    final duration = _toNum(step['duration'] ?? step['length']) ?? 0; // seconds

    // Intervals.icu step may have a nested 'power' map or explicit values.
    num? start;
    num? end;
    num? value;
    String? units;

    final power = step['power'];
    if (power is Map) {
      final pMap = power;
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

    final isRamp = (step['ramp'] == true) && start != null && end != null;
    final isFreeRide = step['freeride'] == true || (value != null && value == 0 && (step['freeride'] ?? false));

    // Collect text if present. Intervals.icu provides 'text' field.
    final text = step['text']?.toString();
    if (text != null && text.trim().isNotEmpty) {
      textCollector.add(text, textCollector.cumulativeTime);
    }

    if (isRamp) {
      // Emit a Ramp block with fractional FTP targets
  final low = scale(start);
  final high = scale(end);
      buffer.writeln('    <Ramp Duration="$duration" PowerLow="$low" PowerHigh="$high"${cadence != null ? ' Cadence="${cadence.toInt()}"' : ''}/>' );
      textCollector.advance(duration.toInt());
      return;
    }

    if (isFreeRide) {
      buffer.writeln('    <FreeRide Duration="$duration"${cadence != null ? ' Cadence="${cadence.toInt()}"' : ''}/>' );
      textCollector.advance(duration.toInt());
      return;
    }

    // Steady state: if both start & end provided but not ramp, use average as per Intervals.icu convention.
    num? avg;
    if (start != null && end != null) {
      avg = (start + end) / 2.0;
    }
    final steadyVal = avg ?? value ?? start ?? end ?? 0;
    buffer.writeln('    <SteadyState Duration="$duration" Power="${scale(steadyVal)}"${cadence != null ? ' Cadence="${cadence.toInt()}"' : ''}/>' );
    textCollector.advance(duration.toInt());
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
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

class _CollectedTextEvent {
  final int timeOffset; // seconds from workout start
  final String message;
  final int duration = 10;
  _CollectedTextEvent(this.timeOffset, this.message);
}

class _TextEventCollector {
  final List<_CollectedTextEvent> events = [];
  int cumulativeTime = 0;

  void add(String message, int timeOffset) {
    events.add(_CollectedTextEvent(timeOffset, message));
  }

  void advance(int seconds) {
    cumulativeTime += seconds;
  }
}