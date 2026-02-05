
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
    
    // Attempt to find FTP in multiple locations
    num? ftp = _toNum(workoutDoc['ftp']);
    if (ftp == null && workoutDoc['sportSettings'] is Map) {
      ftp = _toNum(workoutDoc['sportSettings']['ftp']);
    }
    
    // Debug print
    print('IntervalsConverter: Converting "$name". Found FTP: $ftp');
    
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
    _emitSteps(buffer, steps, textCollector: textCollector, ftp: ftp);
    
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
  
  static void _emitSteps(StringBuffer buffer, dynamic steps, {required _TextEventCollector textCollector, num? ftp}) {
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
          _emitSteps(buffer, step['steps'], textCollector: textCollector, ftp: ftp);
        }
        continue;
      }
      _convertSingleStep(buffer, step, textCollector: textCollector, ftp: ftp);
    }
  }

  static num? _toNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  static void _convertSingleStep(StringBuffer buffer, Map<String, dynamic> step, {required _TextEventCollector textCollector, num? ftp}) {
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

    bool convertedToAbsolute = false;

    // Handle "power_zone" units by using the calculated absolute watts from "_power"
    // and converting to %FTP for ZWO.
    // Check case-insensitive and handle variations
    final isPowerZone = units != null && (
      units!.toLowerCase() == 'power_zone' || 
      units!.toLowerCase().replaceAll('_', '') == 'powerzone'
    );

    if (isPowerZone) {
      // If we have FTP, try to use high-precision absolute watts from _power
      if (ftp != null && ftp > 0) {
        final calculatedPower = step['_power'];
        if (calculatedPower is Map) {
          final wStart = _toNum(calculatedPower['start'] ?? calculatedPower['low']);
          final wEnd = _toNum(calculatedPower['end'] ?? calculatedPower['high']);
          final wValue = _toNum(calculatedPower['value'] ?? calculatedPower['target']);

          // Only override if we have valid watts
          if (wStart != null) start = wStart / ftp;
          if (wEnd != null) end = wEnd / ftp;
          if (wValue != null) value = wValue / ftp;
          
          if (wStart != null || wEnd != null || wValue != null) {
            convertedToAbsolute = true;
          }
        } else {
           print('IntervalsConverter: "power_zone" used but "_power" field missing or invalid.');
        }
      } else {
         print('IntervalsConverter: "power_zone" used but FTP not found ($ftp). Cannot convert absolute watts.');
      }
    }

    if (value == null && start != null && end == null) value = start; // treat single value as steady

    double scale(num v) {
      // If we already converted to absolute fraction, don't scale again OR if units is %ftp
      if (convertedToAbsolute || units == null || units == '%ftp' || units.toLowerCase().contains('%ftp')) {
        if (!convertedToAbsolute) return v / 100.0; // convert %ftp to fraction
        return v.toDouble();
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
    
    // Check if we should use Zone attribute instead of Power
    if (isPowerZone && !convertedToAbsolute) {
      // Fallback to Zone attribute since we couldn't calculate absolute power
      buffer.writeln('    <SteadyState Duration="$duration" Zone="${steadyVal.toInt()}"${cadence != null ? ' Cadence="${cadence.toInt()}"' : ''}/>' );
    } else {
      buffer.writeln('    <SteadyState Duration="$duration" Power="${scale(steadyVal)}"${cadence != null ? ' Cadence="${cadence.toInt()}"' : ''}/>' );
    }
    
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