import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/workout/workout_parser.dart';

void main() {
  test('Parses test.zwo and dumps readable workout object', () async {
    // 1. Read the ZWO file
    final zwoFile = File('test/test.zwo');
    if (!await zwoFile.exists()) {
      fail('Checked-in fixture test/test.zwo not found.');
    }
    final zwoContent = await zwoFile.readAsString();

    // 2. Parse the ZWO content
    final workoutData = WorkoutParser.parseZwoFile(zwoContent);

    expect(workoutData.name, isNotEmpty);
    expect(workoutData.segments, isNotEmpty);

    final dumpDir = await Directory.systemTemp.createTemp(
      'parsed_workout_dump',
    );
    try {
      // 3. Create a human-readable dump
      final buffer = StringBuffer();
      buffer.writeln('Workout Name: ${workoutData.name}');
      // buffer.writeln('Author: ${workoutData.author}'); // Not available in WorkoutData
      // buffer.writeln('Description: ${workoutData.description}'); // description is not public on WorkoutData currently? Let's check.
      // buffer.writeln('Tags: ${workoutData.tags.join(', ')}'); // tags not available
      buffer.writeln(
        'Total Duration: ${_formatDuration(workoutData.segments.fold(0, (sum, seg) => sum + seg.duration))}\n',
      );

      buffer.writeln('--- Segments ---');
      int timeOffset = 0;

      for (int i = 0; i < workoutData.segments.length; i++) {
        final seg = workoutData.segments[i];
        final startStr = _formatDuration(timeOffset);
        final durStr = _formatDuration(seg.duration);
        final endStr = _formatDuration(timeOffset + seg.duration);

        buffer.write('[$startStr - $endStr] (${durStr}) ');
        buffer.write('${seg.type.toString().split('.').last.toUpperCase()}: ');

        if (seg.isRamp) {
          buffer.write(
            'Ramp from ${(seg.powerLow * 100).toStringAsFixed(1)}% to ${(seg.powerHigh * 100).toStringAsFixed(1)}% FTP',
          );
        } else {
          buffer.write(
            'Steady ${(seg.powerLow * 100).toStringAsFixed(1)}% FTP',
          );
        }

        if (seg.cadence != null) {
          buffer.write(' @ ${seg.cadence} rpm');
        }

        if (seg.textEvents.isNotEmpty) {
          buffer.writeln();
          for (final te in seg.textEvents) {
            // Note: textEvents are relative to segment start in some contexts, but usually parsed absolutely or relatively.
            // In WorkoutController they are often handled globally.
            // WorkoutParser attaches them to segments if nested.
            buffer.writeln(
              '      -> Msg: "${te.message}" at +${te.timeOffset}s',
            );
          }
        }
        buffer.writeln();

        timeOffset += seg.duration;
      }

      // 4. Write to a temporary diagnostic file
      final dumpFile = File(
        '${dumpDir.path}${Platform.pathSeparator}dump_parsed_workout.txt',
      );
      await dumpFile.writeAsString(buffer.toString());
      print(
        'Parsed readable workout dump written to: ${dumpFile.absolute.path}',
      );
    } finally {
      await dumpDir.delete(recursive: true);
    }
  });
}

String _formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}
