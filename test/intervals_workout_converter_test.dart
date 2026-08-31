import 'dart:convert';
import 'dart:io';

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
            'power': {'start': 50.0, 'end': 70.0, 'units': '%ftp'},
          },
        ],
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
            'power': {'start': 40.0, 'end': 80.0, 'units': '%ftp'},
          },
        ],
      };
      final xml = IntervalsWorkoutConverter.convertToZwo(doc);
      expect(xml.contains('<Ramp'), isTrue);
      expect(xml.contains('PowerLow="0.4"'), isTrue);
      expect(xml.contains('PowerHigh="0.8"'), isTrue);
      expect(xml.contains('<SteadyState'), isFalse);
    });

    test('embeds text events inside generated segment elements', () {
      final doc = {
        'name': 'TextFreeRide',
        'steps': [
          {
            'duration': 120,
            'text': 'Warmup ramp',
            'ramp': true,
            'power': {'start': 40.0, 'end': 60.0, 'units': '%ftp'},
          },
          {
            'duration': 300,
            'text': 'Go free',
            'freeride': true,
            'power': {'value': 0.0, 'units': '%ftp'},
          },
          {
            'duration': 180,
            'text': 'Steady sweet spot',
            'power': {'value': 88.0, 'units': '%ftp'},
          },
        ],
      };
      final xml = IntervalsWorkoutConverter.convertToZwo(doc);
      // Segment elements
      expect(xml.contains('<Ramp'), isTrue);
      expect(xml.contains('<FreeRide'), isTrue);
      expect(xml.contains('<SteadyState'), isTrue);
      // Text events should be embedded inside each segment instead of a global block
      expect(xml.contains('<textevents>'), isFalse);
      expect(
        xml.contains('message="Warmup ramp 2min ramp 40-60% ftp."'),
        isTrue,
      );
      expect(xml.contains('message="Go free 5min free ride."'), isTrue);
      expect(xml.contains('message="Steady sweet spot 3min 88% ftp."'), isTrue);
    });

    test('converts power_zone units using _power values', () {
      final doc = {
        'name': 'PowerZoneTest',
        'ftp': 300,
        'steps': [
          {
            'duration': 60,
            'power': {'value': 1, 'units': 'power_zone'},
            '_power': {'value': 150.0, 'start': 150.0, 'end': 150.0},
          },
        ],
      };
      final xml = IntervalsWorkoutConverter.convertToZwo(doc);
      // 150 / 300 = 0.5
      expect(xml.contains('Power="0.5"'), isTrue);
    });

    test('falls back to description prefix when name missing', () {
      final doc = {
        'description': 'Intermittent: High/low efforts',
        'steps': [],
      };

      final xml = IntervalsWorkoutConverter.convertToZwo(doc);
      expect(xml.contains('<name>Intermittent</name>'), isTrue);
    });

    test('converts fixture in memory', () async {
      final jsonFile = File('test/test.json');
      expect(
        await jsonFile.exists(),
        isTrue,
        reason: 'Fixture test/test.json missing',
      );

      final Map<String, dynamic> doc =
          jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
      final xml = IntervalsWorkoutConverter.convertToZwo(doc);

      expect(
        xml.contains('<textevent'),
        isTrue,
        reason: 'Converted workout should embed interval text',
      );
      expect(xml.contains('<workout_file>'), isTrue);
      expect(
        xml.contains('<name>Intermittent</name>'),
        isTrue,
        reason: 'Should derive title from description prefix.',
      );
      expect(
        xml.contains(
          'For this first interval let&apos;s aim for 10min ramp 40-73% ftp 90rpm.',
        ),
        isTrue,
        reason: 'Should include enriched first-step summary.',
      );
    });
  });
}
