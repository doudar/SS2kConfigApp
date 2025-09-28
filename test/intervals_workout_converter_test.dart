import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/services/intervals_workout_converter.dart';

void main() {
  group('IntervalsWorkoutConverter', () {
    test('converts steady start/end to averaged SteadyState', () {
      final doc = {
        'name': 'Test',
        'steps': [
          {
            'duration': 60,
            'power': {'start': 50.0, 'end': 70.0, 'units': '%ftp'}
          }
        ]
      };
      final xml = IntervalsWorkoutConverter.convertToZwo(doc);
      expect(xml.contains('<SteadyState'), isTrue);
      // average (50+70)/2 = 60% -> 0.6 fraction
      expect(xml.contains('Power="0.6"'), isTrue);
      expect(xml.contains('<Ramp'), isFalse);
    });

    test('converts ramp=true to Ramp element with start/end', () {
      final doc = {
        'name': 'RampTest',
        'steps': [
          {
            'duration': 120,
            'ramp': true,
            'power': {'start': 40.0, 'end': 80.0, 'units': '%ftp'}
          }
        ]
      };
      final xml = IntervalsWorkoutConverter.convertToZwo(doc);
      expect(xml.contains('<Ramp'), isTrue);
      expect(xml.contains('PowerLow="0.4"'), isTrue);
      expect(xml.contains('PowerHigh="0.8"'), isTrue);
      expect(xml.contains('<SteadyState'), isFalse);
    });

    test('converts text events and FreeRide segments', () {
      final doc = {
        'name': 'TextFreeRide',
        'steps': [
          {
            'duration': 120,
            'text': 'Warmup ramp',
            'ramp': true,
            'power': {'start': 40.0, 'end': 60.0, 'units': '%ftp'}
          },
          {
            'duration': 300,
            'text': 'Go free',
            'freeride': true,
            'power': {'value': 0.0, 'units': '%ftp'}
          },
          {
            'duration': 180,
            'text': 'Steady sweet spot',
            'power': {'value': 88.0, 'units': '%ftp'}
          }
        ]
      };
      final xml = IntervalsWorkoutConverter.convertToZwo(doc);
      // Segment elements
      expect(xml.contains('<Ramp'), isTrue);
      expect(xml.contains('<FreeRide'), isTrue);
      expect(xml.contains('<SteadyState'), isTrue);
      // Text events block with correct cumulative offsets: 0, 120, 420
      expect(xml.contains('<textevent timeoffset="0"'), isTrue);
      expect(xml.contains('message="Warmup ramp"'), isTrue);
      expect(xml.contains('<textevent timeoffset="120"'), isTrue);
      expect(xml.contains('message="Go free"'), isTrue);
      expect(xml.contains('<textevent timeoffset="420"'), isTrue); // 120+300
      expect(xml.contains('message="Steady sweet spot"'), isTrue);
    });
  });
}
