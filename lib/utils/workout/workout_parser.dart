import 'package:xml/xml.dart';
import 'workout_constants.dart';

enum SegmentType {
  steadyState,
  warmup,
  cooldown,
  ramp,
  intervalT,
  freeRide,
  maxEffort
}

class TextEvent {
  final int timeOffset; // Time in seconds from start of segment
  final String message;
  final int? locIndex;
  final int duration; // Duration in seconds to show the message (defaults to 10)
  final int fadeOutDuration; // Duration in seconds to fade out (defaults to 3)

  TextEvent({
    required this.timeOffset,
    required this.message,
    this.locIndex,
    this.duration = 10,
    this.fadeOutDuration = 3,
  });

  // Helper to get the total duration including fade out
  int get totalDuration => duration + fadeOutDuration;

  // Helper to check if the event should be visible at a given time
  bool isVisibleAt(int timeFromSegmentStart) {
    return timeFromSegmentStart >= timeOffset && 
           timeFromSegmentStart < (timeOffset + totalDuration);
  }

  // Helper to get opacity at a given time (1.0 = fully visible, 0.0 = invisible)
  double getOpacityAt(int timeFromSegmentStart) {
    if (!isVisibleAt(timeFromSegmentStart)) return 0.0;
    
    final timeInEvent = timeFromSegmentStart - timeOffset;
    if (timeInEvent < duration) return 1.0;
    
    // Calculate fade out opacity
    final fadeOutProgress = (timeInEvent - duration) / fadeOutDuration;
    return 1.0 - fadeOutProgress;
  }
}

class WorkoutData {
  final String? name;
  final String? description;
  final String? category;
  final String? subcategory;
  final String? authorIcon;
  final List<WorkoutSegment> segments;

  WorkoutData({
    this.name,
    this.description,
    this.category,
    this.subcategory,
    this.authorIcon,
    required this.segments,
  });
}

class WorkoutSegment {
  final SegmentType type;
  final int duration; // Duration in seconds
  final double powerLow; // Power as percentage of FTP (0.0 to 1.0)
  final double powerHigh; // For ramp/warmup/cooldown segments
  final bool isRamp; // Whether power changes over time
  final int? repeat; // For intervals
  final int? onDuration; // For intervals
  final int? offDuration; // For intervals
  final double? onPower; // For intervals
  final double? offPower; // For intervals
  final String? cadence; // Optional cadence target
  final String? cadenceLow; // Optional cadence range
  final String? cadenceHigh; // Optional cadence range
  final List<TextEvent> textEvents; // Text events during the segment

  WorkoutSegment({
    required this.type,
    required this.duration,
    required this.powerLow,
    this.powerHigh = 0.0,
    this.isRamp = false,
    this.repeat,
    this.onDuration,
    this.offDuration,
    this.onPower,
    this.offPower,
    this.cadence,
    this.cadenceLow,
    this.cadenceHigh,
    List<TextEvent>? textEvents,
  }) : textEvents = textEvents ?? [];

  // Helper to get current power at a specific point in the segment
  double getPowerAtTime(int secondsFromStart) {
    if (!isRamp) return powerLow;
    
    final progress = secondsFromStart / duration;
    
    // For cooldowns, we want to start at powerHigh and end at powerLow
    if (type == SegmentType.cooldown) {
      return powerHigh - (powerHigh - powerLow) * progress;
    }
    
    // For all other segments, start at powerLow and end at powerHigh
    return powerLow + (powerHigh - powerLow) * progress;
  }

  // Helper to get maximum power in the segment
  double get maxPower {
    if (!isRamp) return powerLow;
    return powerHigh > powerLow ? powerHigh : powerLow;
  }

  // Helper to get minimum power in the segment
  double get minPower {
    if (!isRamp) return powerLow;
    return powerLow < powerHigh ? powerLow : powerHigh;
  }

  // Helper to get text events that should be visible at a given time
  List<TextEvent> getVisibleTextEventsAt(int secondsFromStart) {
    return textEvents.where((event) => event.isVisibleAt(secondsFromStart)).toList();
  }
}

class WorkoutParser {
  // Zone to power mapping (as percentage of FTP)
  static const Map<String, Map<String, double>> zonePowerMapping = {
    '1': {'low': 0.44, 'high': 0.55},   // Recovery
    '2': {'low': 0.56, 'high': 0.75},  // Endurance
    '3': {'low': 0.76, 'high': 0.90},  // Tempo
    '4': {'low': 0.91, 'high': 1.05},  // Threshold
    '5': {'low': 1.06, 'high': 1.20},  // VO2 Max
    '6': {'low': 1.21, 'high': 1.50},  // Anaerobic
    '7': {'low': 1.51, 'high': 10.00},  // Neuromuscular
  };

  // Helper method to parse duration strings that might be floating point
  static int _parseDuration(String? durationStr) {
    if (durationStr == null) return 0;
    try {
      // Parse as double first to handle floating point values
      final double durationDouble = double.parse(durationStr);
      // Round to nearest integer
      return durationDouble.round();
    } catch (e) {
      // If parsing fails, return 0 as a safe default
      return 0;
    }
  }

  static WorkoutData parseZwoFile(String xmlContent) {
    final document = XmlDocument.parse(xmlContent);
    
    // Find the workout element
    final workoutElements = document.findAllElements('workout');
    if (workoutElements.isEmpty) {
      throw FormatException('No workout element found in .zwo file');
    }
    
    final workoutElement = workoutElements.first;
    
    // Extract workout metadata from root level
    String? workoutName;
    String? description;
    String? category;
    String? subcategory;
    String? authorIcon;

    // First try root level elements
    for (var element in document.rootElement.childElements) {
      switch (element.name.local.toLowerCase()) {
        case 'name':
          workoutName = element.innerText.trim();
          break;
        case 'description':
          description = element.innerText.trim();
          break;
        case 'category':
          category = element.innerText.trim();
          break;
        case 'subcategory':
          subcategory = element.innerText.trim();
          break;
        case 'authoricon':
          authorIcon = element.innerText.trim();
          break;
      }
    }

    // If not found at root level, try within workout element
    if (workoutName == null) {
      final nameElements = workoutElement.findElements('name');
      workoutName = nameElements.isNotEmpty ? nameElements.first.innerText.trim() : null;
    }
    
    // Process segments
    final List<WorkoutSegment> segments = [];
    for (var segment in workoutElement.children) {
      if (segment is! XmlElement) continue;

      final parsedSegments = _parseSegment(segment);
      if (parsedSegments != null) {
        segments.addAll(parsedSegments);
      }
    }
    
    return WorkoutData(
      name: workoutName,
      description: description,
      category: category,
      subcategory: subcategory,
      authorIcon: authorIcon,
      segments: segments,
    );
  }

  static List<WorkoutSegment>? _parseSegment(XmlElement element) {
    final type = element.name.local;
    
    switch (type) {
      case 'SteadyState':
        return [_parseSteadyState(element)];
      
      case 'Warmup':
        return [_parseRampSegment(element, SegmentType.warmup)];
      
      case 'Cooldown':
        return [_parseRampSegment(element, SegmentType.cooldown)];
      
      case 'Ramp':
        return [_parseRampSegment(element, SegmentType.ramp)];
      
      case 'IntervalsT':
        return _parseIntervals(element);
      
      case 'FreeRide':
        return [_parseFreeRide(element)];
      
      case 'MaxEffort':
        return [_parseMaxEffort(element)];
      
      default:
        return null; // Skip unknown segments
    }
  }

  static List<TextEvent> _parseTextEvents(XmlElement element) {
    List<TextEvent> events = [];
    
    // Parse both TextEvent and textevent elements
    for (var eventElement in [...element.findElements('TextEvent'), ...element.findElements('textevent')]) {
      final timeOffset = _parseDuration(eventElement.getAttribute('timeoffset'));
      final message = eventElement.getAttribute('message') ?? '';
      final locIndex = int.tryParse(eventElement.getAttribute('locIndex') ?? '');
      final duration = _parseDuration(eventElement.getAttribute('duration'));
      
      if (message.isNotEmpty) {
        events.add(TextEvent(
          timeOffset: timeOffset,
          message: message,
          locIndex: locIndex,
          duration: duration,
          fadeOutDuration: 3, // Fixed 3-second fade out
        ));
      }
    }
    
    return events;
  }

  static double _getZonePower(String zone, {bool high = false}) {
    final zoneData = zonePowerMapping[zone];
    if (zoneData == null) return 0.0;
    return high ? zoneData['high']! : zoneData['low']!;
  }

  static WorkoutSegment _parseSteadyState(XmlElement element) {
    final duration = _parseDuration(element.getAttribute('Duration'));
    
    // Check for Zone attribute first
    final zone = element.getAttribute('Zone');
    double power;
    if (zone != null) {
      // Use average of zone range (e.g. Zone 2 is 0.56-0.75, avg 0.655)
      // Otherwise we get the bottom of the zone which is too easy
      final zLow = _getZonePower(zone, high: false);
      final zHigh = _getZonePower(zone, high: true);
      power = (zLow + zHigh) / 2.0;
    } else {
      // If no Zone, try Power/PowerLow/PowerHigh attributes
      final powerAttr = element.getAttribute('Power');
      final powerLowAttr = element.getAttribute('PowerLow');
      final powerHighAttr = element.getAttribute('PowerHigh');

      // Check if Power attribute is present and valid
      if (powerAttr != null && powerAttr.isNotEmpty && double.tryParse(powerAttr) != null) {
        power = double.parse(powerAttr);
      } else {
        // If no valid Power attribute, check for range (PowerLow + PowerHigh)
        if (powerLowAttr != null && powerHighAttr != null) {
          // If range provided for steady state, use average
          final pLow = double.tryParse(powerLowAttr) ?? 0.0;
          final pHigh = double.tryParse(powerHighAttr) ?? 0.0;
          power = (pLow + pHigh) / 2.0;
        } else {
          // Fallback to PowerLow if available, or 0.0
          power = double.tryParse(powerLowAttr ?? '0') ?? 0.0;
        }
      }
    }
    
    return WorkoutSegment(
      type: SegmentType.steadyState,
      duration: duration,
      powerLow: power,
      cadence: element.getAttribute('Cadence'),
      cadenceLow: element.getAttribute('CadenceLow'),
      cadenceHigh: element.getAttribute('CadenceHigh'),
      textEvents: _parseTextEvents(element),
    );
  }

  static WorkoutSegment _parseRampSegment(XmlElement element, SegmentType segmentType) {
    final duration = _parseDuration(element.getAttribute('Duration'));
    
    // Check for Zone attribute first
    final zone = element.getAttribute('Zone');
    double powerLow, powerHigh;
    
    if (zone != null) {
      powerLow = _getZonePower(zone, high: false);
      powerHigh = _getZonePower(zone, high: true);
    } else {
      // For cooldowns, if no power values are specified, use defaults
      if (segmentType == SegmentType.cooldown && 
          element.getAttribute('PowerLow') == null && 
          element.getAttribute('PowerHigh') == null) {
        powerLow = defaultCooldownEnd;    // End at 50% FTP
        powerHigh = defaultCooldownStart; // Start at 70% FTP
      } else {
        double power1 = double.parse(element.getAttribute('PowerLow') ?? '0');
        double power2 = double.parse(element.getAttribute('PowerHigh') ?? '0');
        
        // For cooldowns, ensure the higher number is powerHigh
        if (segmentType == SegmentType.cooldown) {
          powerHigh = power1 > power2 ? power1 : power2;
          powerLow = power1 > power2 ? power2 : power1;
        } else {
          powerLow = power1;
          powerHigh = power2;
        }
      }
    }
    
    return WorkoutSegment(
      type: segmentType,
      duration: duration,
      powerLow: powerLow,
      powerHigh: powerHigh,
      isRamp: true,
      cadence: element.getAttribute('Cadence'),
      cadenceLow: element.getAttribute('CadenceLow'),
      cadenceHigh: element.getAttribute('CadenceHigh'),
      textEvents: _parseTextEvents(element),
    );
  }

  static List<WorkoutSegment> _parseIntervals(XmlElement element) {
    final repeat = _parseDuration(element.getAttribute('Repeat'));
    final onDuration = _parseDuration(element.getAttribute('OnDuration'));
    final offDuration = _parseDuration(element.getAttribute('OffDuration'));
    
    // Check for Zone attributes first
    final onZone = element.getAttribute('OnZone');
    final offZone = element.getAttribute('OffZone');
    
    double onPower, offPower;
    
    if (onZone != null) {
      onPower = _getZonePower(onZone);
    } else {
      onPower = double.parse(element.getAttribute('OnPower') ?? '0');
    }
    
    if (offZone != null) {
      offPower = _getZonePower(offZone);
    } else {
      offPower = double.parse(element.getAttribute('OffPower') ?? '0');
    }
    
    final List<WorkoutSegment> intervals = [];
    final textEvents = _parseTextEvents(element);
    
    for (var i = 0; i < repeat; i++) {
      // On interval
      intervals.add(WorkoutSegment(
        type: SegmentType.intervalT,
        duration: onDuration,
        powerLow: onPower,
        onDuration: onDuration,
        offDuration: offDuration,
        onPower: onPower,
        offPower: offPower,
        repeat: repeat,
        cadence: element.getAttribute('Cadence'),
        cadenceLow: element.getAttribute('CadenceLow'),
        cadenceHigh: element.getAttribute('CadenceHigh'),
        textEvents: textEvents,
      ));
      
      // Off interval
      intervals.add(WorkoutSegment(
        type: SegmentType.intervalT,
        duration: offDuration,
        powerLow: offPower,
        onDuration: onDuration,
        offDuration: offDuration,
        onPower: onPower,
        offPower: offPower,
        repeat: repeat,
        cadence: element.getAttribute('Cadence'),
        cadenceLow: element.getAttribute('CadenceLow'),
        cadenceHigh: element.getAttribute('CadenceHigh'),
        textEvents: textEvents,
      ));
    }
    
    return intervals;
  }

  static WorkoutSegment _parseFreeRide(XmlElement element) {
    final duration = _parseDuration(element.getAttribute('Duration'));
    
    return WorkoutSegment(
      type: SegmentType.freeRide,
      duration: duration,
      powerLow: 0.0, // FreeRide has no power target
      cadence: element.getAttribute('Cadence'),
      cadenceLow: element.getAttribute('CadenceLow'),
      cadenceHigh: element.getAttribute('CadenceHigh'),
      textEvents: _parseTextEvents(element),
    );
  }

  static WorkoutSegment _parseMaxEffort(XmlElement element) {
    final duration = _parseDuration(element.getAttribute('Duration'));
    
    return WorkoutSegment(
      type: SegmentType.maxEffort,
      duration: duration,
      powerLow: 1.5, // MaxEffort typically suggests all-out effort (>150% FTP)
      cadence: element.getAttribute('Cadence'),
      cadenceLow: element.getAttribute('CadenceLow'),
      cadenceHigh: element.getAttribute('CadenceHigh'),
      textEvents: _parseTextEvents(element),
    );
  }
}
