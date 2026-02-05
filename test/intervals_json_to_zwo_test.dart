import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/services/intervals_workout_converter.dart';

void main() {
  test('Reads test.json, converts to ZWO, and writes to disk', () async {
    // 1. Read JSON file
    final file = File('test/test.json');
    if (!await file.exists()) {
      fail('test/test.json not found');
    }
    final jsonString = await file.readAsString();
    final Map<String, dynamic> jsonMap = jsonDecode(jsonString);

    // 2. Convert to ZWO
    final zwoOutput = IntervalsWorkoutConverter.convertToZwo(jsonMap);

    // 3. Write output to test/test.zwo
    final outFile = File('test/test.zwo');
    await outFile.writeAsString(zwoOutput);
    
    print('Converted ZWO written to: ${outFile.absolute.path}');

    // 4. Verify content
    expect(zwoOutput, contains('<workout_file>'));
    
    // Check for the specific value we predicted:
    // Zone 1 range in JSON: "_power":{"start":132.0,"end":165.0}
    // Average: 148.5
    // FTP: 300
    // Result: 148.5/300 = 0.495
    expect(zwoOutput.contains('Power="0.495"'), isTrue, reason: 'Should convert Zone 1 range (132-165W) to average ~50% FTP');

    // Make sure we don't have the error case (Power="1")
    // "value":1 in "power" block was triggering 100% FTP erroneously
    expect(zwoOutput.contains('Power="1"'), isFalse, reason: 'Should not default to 100% FTP for Zone 1');
  });
}
