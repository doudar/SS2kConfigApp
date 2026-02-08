
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
    final name = _deriveWorkoutName(workoutDoc, description);
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
    
    _emitSteps(buffer, steps, ftp: ftp);

    buffer.writeln('  </workout>');
    buffer.writeln('</workout_file>');
    
    return buffer.toString();
  }
  
  static void _emitSteps(StringBuffer buffer, dynamic steps, {num? ftp}) {
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
          _emitSteps(buffer, step['steps'], ftp: ftp);
        }
        continue;
      }
      _convertSingleStep(buffer, step, ftp: ftp);
    }
  }

  static num? _toNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  static void _convertSingleStep(StringBuffer buffer, Map<String, dynamic> step, {num? ftp}) {
    final int duration = (_toNum(step['duration'] ?? step['length']) ?? 0).toInt(); // seconds

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
      units.toLowerCase() == 'power_zone' || 
      units.toLowerCase().replaceAll('_', '') == 'powerzone'
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

    final cadence = _extractCadence(step['cadence']);

    final isRamp = (step['ramp'] == true) && start != null && end != null;
    final isFreeRide = step['freeride'] == true || (value != null && value == 0 && (step['freeride'] ?? false));

    final text = step['text']?.toString();
    final textOffset = _toNum(step['text_offset'])?.toInt() ?? 0;
    final textDuration = _toNum(step['text_duration'])?.toInt() ?? 10;

    if (isRamp) {
      // Emit a Ramp block with fractional FTP targets
      final low = scale(start);
      final high = scale(end);
      final rampText = _buildTextEventMessage(
        baseText: text,
        durationSeconds: duration,
        isRamp: true,
        rampLowFraction: low,
        rampHighFraction: high,
        cadenceRpm: cadence,
      );
      _writeSegmentElement(
        buffer,
        'Ramp',
        ' Duration="$duration" PowerLow="$low" PowerHigh="$high"${cadence != null ? ' Cadence="${cadence.toInt()}"' : ''}',
        _buildTextEventXml(rampText, textOffset, textDuration),
      );
      return;
    }

    if (isFreeRide) {
      final freeRideText = _buildTextEventMessage(
        baseText: text,
        durationSeconds: duration,
        isFreeRide: true,
        cadenceRpm: cadence,
      );
      _writeSegmentElement(
        buffer,
        'FreeRide',
        ' Duration="$duration"${cadence != null ? ' Cadence="${cadence.toInt()}"' : ''}',
        _buildTextEventXml(freeRideText, textOffset, textDuration),
      );
      return;
    }

    // Steady state: if both start & end provided but not ramp, use average as per Intervals.icu convention.
    num? avg;
    if (start != null && end != null) {
      avg = (start + end) / 2.0;
    }
    final steadyVal = avg ?? value ?? start ?? end ?? 0;
    
    // Check if we should use Zone attribute instead of Power
    final usesZoneAttribute = isPowerZone && !convertedToAbsolute;
    final steadyFraction = !usesZoneAttribute ? scale(steadyVal) : null;
    final zoneTarget = usesZoneAttribute ? steadyVal.toInt() : null;
    final steadyText = _buildTextEventMessage(
      baseText: text,
      durationSeconds: duration,
      steadyFraction: steadyFraction,
      zoneTarget: zoneTarget,
      cadenceRpm: cadence,
    );

    if (usesZoneAttribute) {
      // Fallback to Zone attribute since we couldn't calculate absolute power
      _writeSegmentElement(
        buffer,
        'SteadyState',
        ' Duration="$duration" Zone="${steadyVal.toInt()}"${cadence != null ? ' Cadence="${cadence.toInt()}"' : ''}',
        _buildTextEventXml(steadyText, textOffset, textDuration),
      );
    } else {
      _writeSegmentElement(
        buffer,
        'SteadyState',
        ' Duration="$duration" Power="${steadyFraction ?? 0}"${cadence != null ? ' Cadence="${cadence.toInt()}"' : ''}',
        _buildTextEventXml(steadyText, textOffset, textDuration),
      );
    }
  }

  static void _writeSegmentElement(StringBuffer buffer, String tagName, String attributes, String? textEventXml) {
    if (textEventXml != null) {
      buffer.writeln('    <$tagName$attributes>');
      buffer.writeln(textEventXml);
      buffer.writeln('    </$tagName>');
    } else {
      buffer.writeln('    <$tagName$attributes/>' );
    }
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
  
  static String _deriveWorkoutName(Map<String, dynamic> doc, String? description) {
    final preferredKeys = ['name', 'title', 'workoutName'];
    for (final key in preferredKeys) {
      final value = doc[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    if (description != null && description.trim().isNotEmpty) {
      final trimmed = description.trim();
      final delimiterIndex = trimmed.indexOf(':');
      if (delimiterIndex > 0) {
        final candidate = trimmed.substring(0, delimiterIndex).trim();
        if (candidate.isNotEmpty) {
          return candidate;
        }
      }

      final firstLine = trimmed.split(RegExp(r'[\r\n]')).first.trim();
      if (firstLine.isNotEmpty) {
        return firstLine.length > 80 ? firstLine.substring(0, 80).trim() : firstLine;
      }
    }

    return 'Intervals.icu Workout';
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

  static double? _extractCadence(dynamic cadenceField) {
    if (cadenceField == null) return null;
    if (cadenceField is num) return cadenceField.toDouble();
    if (cadenceField is String) return double.tryParse(cadenceField);
    if (cadenceField is Map) {
      final value = cadenceField['value'];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
    }
    return null;
  }

  static String? _buildTextEventMessage({
    String? baseText,
    required int durationSeconds,
    bool isRamp = false,
    bool isFreeRide = false,
    double? rampLowFraction,
    double? rampHighFraction,
    double? steadyFraction,
    int? zoneTarget,
    double? cadenceRpm,
  }) {
    final List<String> summaryParts = [];
    final durationLabel = _formatDurationLabel(durationSeconds);
    if (durationLabel != null) {
      summaryParts.add(durationLabel);
    }

    if (isRamp && rampLowFraction != null && rampHighFraction != null) {
      summaryParts.add('ramp ${_formatPercent(rampLowFraction)}-${_formatPercent(rampHighFraction)}% ftp');
    } else if (isFreeRide) {
      summaryParts.add('free ride');
    } else if (zoneTarget != null) {
      summaryParts.add('Zone $zoneTarget');
    } else if (steadyFraction != null) {
      summaryParts.add('${_formatPercent(steadyFraction)}% ftp');
    }

    if (cadenceRpm != null) {
      summaryParts.add('${cadenceRpm.round()}rpm');
    }

    final trimmedBase = baseText?.trim() ?? '';

    if (summaryParts.isEmpty) {
      return trimmedBase.isEmpty ? null : trimmedBase;
    }

    final summaryText = summaryParts.join(' ');
    final summaryNeedsPeriod = summaryText.isNotEmpty && !_endsWithTerminal(summaryText);
    final summaryWithPunctuation = summaryText.isEmpty
        ? ''
        : summaryNeedsPeriod
            ? '$summaryText.'
            : summaryText;

    if (trimmedBase.isEmpty) {
      return summaryWithPunctuation.isEmpty ? null : summaryWithPunctuation;
    }

    final separator = trimmedBase.endsWith(' ') ? '' : ' ';
    final baseNeedsSpace = summaryWithPunctuation.isNotEmpty;
    final combined = baseNeedsSpace
        ? trimmedBase + separator + summaryWithPunctuation
        : trimmedBase;

    if (_endsWithTerminal(combined)) {
      return combined;
    }

    return '$combined.';
  }

  static String? _formatDurationLabel(int seconds) {
    if (seconds <= 0) return null;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    final buffer = StringBuffer();
    if (hours > 0) buffer.write('${hours}hr');
    if (minutes > 0) buffer.write('${minutes}min');
    if (secs > 0 || buffer.isEmpty) buffer.write('${secs}sec');
    return buffer.toString();
  }

  static String _formatPercent(double fraction) {
    final percent = (fraction * 100).clamp(-1000.0, 10000.0);
    final rounded = percent.round();
    return rounded.toString();
  }

  static bool _endsWithTerminal(String value) {
    if (value.isEmpty) return false;
    const terminals = ['.', '!', '?'];
    return terminals.any((terminal) => value.trim().endsWith(terminal));
  }

  static String? _buildTextEventXml(String? message, int offset, int duration) {
    if (message == null || message.trim().isEmpty) return null;
    return '      <textevent timeoffset="$offset" message="${_escapeXml(message.trim())}" duration="$duration"/>';
  }
}