/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import './device_data.dart';
import './snackbar.dart';
import './power_table_management.dart';
import './constants.dart';

class PowerTableSharing {
  // Convert power table data to CSV format
  static String convertToCSV(
    List<List<int?>> powerTableData,
    String? hMaxValue,
  ) {
    final StringBuffer csv = StringBuffer();

    // Add metadata header for HMax (if available)
    if (hMaxValue != null && hMaxValue != noFirmSupport) {
      csv.write('# METADATA:HMax=${hMaxValue}\n');
    }

    // Add header row with power values (0-1000W in 30W increments)
    csv.write('Cadence/Power,');
    for (int i = 0; i < 38; i++) {
      csv.write('${i * 30}W');
      if (i < 37) csv.write(',');
    }
    csv.write('\n');

    // Add data rows with cadence values (60-105 RPM)
    final List<int> cadences = [60, 65, 70, 75, 80, 85, 90, 95, 100, 105];
    for (int i = 0; i < powerTableData.length; i++) {
      csv.write('${cadences[i]}RPM,');
      for (int j = 0; j < powerTableData[i].length; j++) {
        csv.write(powerTableData[i][j]?.toString() ?? '');
        if (j < powerTableData[i].length - 1) csv.write(',');
      }
      csv.write('\n');
    }

    return csv.toString();
  }

  // Parse CSV data back into power table format with option for HMax
  static Map<String, dynamic> parseCSV(String csvContent) {
    final List<String> lines = LineSplitter.split(csvContent).toList();
    final List<List<int?>> powerTableData = [];
    String? hMaxValue;

    // Process lines
    int startIndex = 0;

    // Check for metadata in the first line
    if (lines.isNotEmpty && lines[0].startsWith('# METADATA:')) {
      String metadataLine = lines[0];
      startIndex = 1; // Skip metadata line

      // Parse HMax value if present
      RegExp hmaxRegex = RegExp(r'HMax=(\d+)');
      RegExpMatch? match = hmaxRegex.firstMatch(metadataLine);
      if (match != null && match.groupCount >= 1) {
        hMaxValue = match.group(1);
      }
    }

    // Skip header row (starts after metadata if present)
    for (int i = startIndex + 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;

      final List<String> values = lines[i].split(',');
      final List<int?> row = [];

      // Skip the cadence column (first column)
      for (int j = 1; j < values.length; j++) {
        final value = values[j].trim();
        row.add(value.isEmpty ? null : int.parse(value));
      }

      powerTableData.add(row);
    }

    return {'powerTable': powerTableData, 'hMax': hMaxValue};
  }

  // Export power table as .ptab file
  static Future<void> exportPowerTable(
    BuildContext context,
    DeviceData deviceData,
    String fileName,
  ) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final String filePath = '${directory.path}/$fileName.ptab';

      // Get HMax value
      String hMaxValue = deviceData.getVnameValue(BLE_hMaxVname);

      // Convert power table to CSV including HMax and save to temporary file
      final String csvContent = convertToCSV(
        deviceData.powerTableData,
        hMaxValue != noFirmSupport ? hMaxValue : null,
      );
      await File(filePath).writeAsString(csvContent);

      // Get the RenderBox for positioning the share dialog on macOS
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      Rect? sharePositionOrigin;

      if (box != null) {
        final offset = box.localToGlobal(Offset.zero);
        sharePositionOrigin = offset & box.size;
      }

      // Share the file with proper positioning
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: 'SmartSpin2k Power Table',
          subject: fileName,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

      // Clean up temporary file
      await File(filePath).delete();

      if (context.mounted) {
        switch (result.status) {
          case ShareResultStatus.success:
            Snackbar.show(
              ABC.c,
              "Power table exported successfully",
              success: true,
            );
            break;
          case ShareResultStatus.dismissed:
            Snackbar.show(ABC.c, "Export cancelled", success: false);
            break;
          case ShareResultStatus.unavailable:
            Snackbar.show(ABC.c, "Sharing not available", success: false);
            break;
        }
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          "Failed to export power table: $e",
          success: false,
        );
      }
    }
  }

  // Import power table from .ptab file
  static Future<void> importPowerTable(
    BuildContext context,
    DeviceData deviceData, [
    BluetoothDevice? device,
  ]) async {
    try {
      // Pick file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result == null || !context.mounted) return;

      // Read file content
      final File file = File(result.files.single.path!);
      final String csvContent = await file.readAsString();

      // Get filename without extension for save name
      final String saveName = result.files.single.name.replaceAll('.ptab', '');

      // Check for duplicate name
      final bool isDuplicate = await PowerTableManager.isTableNameExists(
        saveName,
      );
      if (isDuplicate) {
        if (!context.mounted) return;
        final bool? overwrite = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Duplicate Name'),
              content: Text(
                'A power table with the name "$saveName" already exists. Do you want to overwrite it?',
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                TextButton(
                  child: Text('Overwrite'),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            );
          },
        );

        if (overwrite != true || !context.mounted) return;
      }

      // Parse CSV content
      final Map<String, dynamic> parsedData = parseCSV(csvContent);
      final List<List<int?>> importedPowerTable =
          parsedData['powerTable'] as List<List<int?>>;
      final String? importedHMax = parsedData['hMax'] as String?;

      // Update power table data
      deviceData.powerTableData = importedPowerTable;

      // If device is provided, send the power table to the device
      bool sentToDevice = false;
      if (device != null) {
        sentToDevice = await PowerTableManager.sendPowerTableToDevice(
          context,
          deviceData,
          device,
          hMaxValue: importedHMax,
        );
      }

      // Save imported table
      if (context.mounted) {
        await PowerTableManager.savePowerTable(context, deviceData, saveName);

        // Show appropriate message based on whether the table was sent to device
        if (sentToDevice) {
          Snackbar.show(
            ABC.c,
            "Power table imported, saved, and sent to device",
            success: true,
          );
        } else if (device != null) {
          Snackbar.show(
            ABC.c,
            "Power table imported and saved, but failed to send to device",
            success: false,
          );
        } else {
          Snackbar.show(ABC.c, "Power table imported and saved", success: true);
        }
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          "Failed to import power table: $e",
          success: false,
        );
      }
    }
  }
}
