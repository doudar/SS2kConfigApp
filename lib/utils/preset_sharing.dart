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
import 'package:universal_ble/universal_ble.dart';
import './bledata.dart';
import './snackbar.dart';
import './presets.dart';
import './constants.dart';

class PresetSharing {
  static Future<bool> _ensureDeviceConnected(BuildContext context, BLEData bleData) async {
    if (bleData.isSimulated) {
      return true;
    }
    try {
      final state = await UniversalBle.getConnectionState(bleData.deviceId);
      if (state == BleConnectionState.connected) {
        return true;
      }
    } catch (e) {
      debugPrint('Failed to determine connection state: $e');
    }
    if (context.mounted) {
      Snackbar.show(ABC.c, "Device not connected", success: false);
    }
    return false;
  }

  // Export preset as .ss2k file
  static Future<void> exportPreset(BuildContext context, BLEData bleData, String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final String filePath = '${directory.path}/$fileName.ss2k';
      
      // Convert settings to JSON, excluding sensitive data and complex objects
      List<Map<String, dynamic>> exportList = [];
      for (var item in bleData.customCharacteristic) {
        if (item is Map && item.containsKey('vName') && item.containsKey('value')) {
          if (item['vName'] != ssidVname && item['vName'] != passwordVname) {
            exportList.add({
              'vName': item['vName'],
              'value': item['value'],
            });
          }
        }
      }
      String jsonContent = jsonEncode(exportList);
      
      await File(filePath).writeAsString(jsonContent);

      // Get the RenderBox for positioning the share dialog on macOS
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      Rect? sharePositionOrigin;
      
      if (box != null) {
        final offset = box.localToGlobal(Offset.zero);
        sharePositionOrigin = offset & box.size;
      }
      
      // Share the file with proper positioning
      final result = await Share.shareXFiles(
        [XFile(filePath)],
        text: 'SmartSpin2k Settings Preset',
        subject: fileName,
        sharePositionOrigin: sharePositionOrigin,
      );
      
      // Clean up temporary file
      await File(filePath).delete();
      
      if (context.mounted) {
        switch (result.status) {
          case ShareResultStatus.success:
            Snackbar.show(ABC.c, "Preset exported successfully", success: true);
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
        Snackbar.show(ABC.c, "Failed to export preset: $e", success: false);
      }
    }
  }

  // Import preset from .ss2k or .json file
  static Future<void> importPreset(BuildContext context, BLEData bleData) async {
    try {
      // Pick file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result == null || !context.mounted) return;

      // Read file content
      final File file = File(result.files.single.path!);
      final String jsonContent = await file.readAsString();
      
      // Get filename without extension for save name
      String saveName = result.files.single.name;
      if (saveName.toLowerCase().endsWith('.ss2k')) {
        saveName = saveName.substring(0, saveName.length - 5);
      } else if (saveName.toLowerCase().endsWith('.json')) {
        saveName = saveName.substring(0, saveName.length - 5);
      }
      
      // Check for duplicate name
      // Note: We need to access shared prefs to check for duplicates, which is done in PresetManager
      // Since isPresetNameExists isn't public, we'll try to save and let the user decide if they want to overwrite
      // Parse JSON content to validate it
      try {
        final dynamic decoded = jsonDecode(jsonContent);
        if (decoded is! List) throw FormatException("Invalid preset format");

        List<dynamic> currentConfig = List.from(bleData.customCharacteristic);
        List<dynamic> importedConfig = decoded;

        List<dynamic> mergedConfig = currentConfig.map((item) {
          var currentMap = Map<String, dynamic>.from(item);

          if (currentMap['vName'] == ssidVname || currentMap['vName'] == passwordVname) {
            return currentMap;
          }

          var matchingImported = importedConfig.where((element) => element['vName'] == currentMap['vName']);
          var importedItem = matchingImported.isNotEmpty ? matchingImported.first : null;

          if (importedItem != null) {
            if (importedItem['value'] != null) {
              currentMap['value'] = importedItem['value'];
            } else if (importedItem['defaultData'] != null) {
              currentMap['value'] = importedItem['defaultData'];
            }
          }
          return currentMap;
        }).toList();

        final previousSettings = bleData.customCharacteristic;
        try {
          bleData.customCharacteristic = mergedConfig;
          await PresetManager.savePreset(context, bleData, saveName);
        } finally {
          bleData.customCharacteristic = previousSettings;
        }

        if (context.mounted) {
          bool? applyNow = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('Import Successful'),
                content: Text('Preset "${saveName}" imported. Do you want to apply these settings to your device now?'),
                actions: <Widget>[
                  TextButton(
                    child: Text('No, save only'),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  FilledButton(
                    child: Text('Yes, apply now'),
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              );
            },
          );

          if (applyNow == true) {
            final connected = await _ensureDeviceConnected(context, bleData);
            if (connected) {
              try {
                bleData.customCharacteristic = mergedConfig;
                await bleData.saveAllSettings();
                Snackbar.show(ABC.c, "Settings applied to device", success: true);
              } finally {
                bleData.customCharacteristic = previousSettings;
              }
            }
          } else {
            Snackbar.show(ABC.c, "Preset saved to My Files", success: true);
          }
        }
      } catch (e) {
        if (context.mounted) {
          Snackbar.show(ABC.c, "Invalid preset file: $e", success: false);
        }
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(ABC.c, "Failed to import preset: $e", success: false);
      }
    }
  }
}
