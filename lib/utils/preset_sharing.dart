/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import './device_data.dart';
import './snackbar.dart';
import './presets.dart';
import './constants.dart';
import '../widgets/settings_backup_name_dialog.dart';

class PresetSharing {
  // Export preset as .ss2k file
  static Future<void> exportPreset(
    BuildContext context,
    DeviceData deviceData,
    String fileName,
  ) async {
    Directory? exportDirectory;
    try {
      final directory = await getTemporaryDirectory();
      exportDirectory = await directory.createTemp('ss2k_settings_');
      final String filePath = '${exportDirectory.path}/$fileName.ss2k';

      // Convert settings to JSON, excluding sensitive data and complex objects
      List<Map<String, dynamic>> exportList = [];
      for (var item in deviceData.customCharacteristic) {
        if (item.containsKey('vName') && item.containsKey('value')) {
          if (item['vName'] != ssidVname && item['vName'] != passwordVname) {
            exportList.add({'vName': item['vName'], 'value': item['value']});
          }
        }
      }
      String jsonContent = jsonEncode(exportList);

      await File(filePath).writeAsString(jsonContent);
      if (!context.mounted) return;

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
          text: 'SmartSpin2k settings',
          subject: fileName,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

      if (context.mounted) {
        switch (result.status) {
          case ShareResultStatus.success:
            Snackbar.show(
              ABC.c,
              'Settings file shared or saved.',
              success: true,
            );
            break;
          case ShareResultStatus.dismissed:
            break;
          case ShareResultStatus.unavailable:
            // Some platforms show the share sheet but cannot report its result.
            break;
        }
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          'Could not export the settings file. Please try again.',
          success: false,
        );
      }
    } finally {
      if (exportDirectory != null)
        await exportDirectory.delete(recursive: true);
    }
  }

  // Keep file selection separate from decoding and the save/load decision.
  static Future<void> importPreset(
    BuildContext context,
    DeviceData deviceData,
    BluetoothDevice device,
  ) async {
    try {
      final pickedFile = await FilePicker.pickFile(type: FileType.any);
      if (pickedFile == null || !context.mounted) return;
      final jsonContent = utf8.decode(await pickedFile.readAsBytes());
      if (!context.mounted) return;
      await importPresetContent(
        context,
        deviceData,
        device,
        jsonContent,
        pickedFile.name,
      );
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          'Could not open this file. Choose a SmartSpin2k .ss2k or .json settings file.',
          success: false,
        );
      }
    }
  }

  static Future<void> importPresetContent(
    BuildContext context,
    DeviceData deviceData,
    BluetoothDevice device,
    String jsonContent,
    String fileName,
  ) async {
    late final List<Map<String, dynamic>> mergedConfig;
    try {
      final decoded = jsonDecode(jsonContent);
      if (decoded is! List ||
          decoded.isEmpty ||
          decoded.any((item) => item is! Map || item['vName'] is! String)) {
        throw const FormatException('Invalid settings file');
      }
      final imported = {
        for (final item in decoded) item['vName'] as String: item,
      };
      final hasSettings = deviceData.customCharacteristic.any(
        (item) =>
            item['isSetting'] == true &&
            item['vName'] != ssidVname &&
            item['vName'] != passwordVname &&
            (imported[item['vName']]?['value'] != null ||
                imported[item['vName']]?['defaultData'] != null),
      );
      if (!hasSettings) throw const FormatException('No matching settings');

      mergedConfig = deviceData.customCharacteristic.map((item) {
        final current = Map<String, dynamic>.from(item);
        if (current['vName'] != ssidVname &&
            current['vName'] != passwordVname) {
          final match = imported[current['vName']];
          if (match != null && (match['value'] ?? match['defaultData']) != null)
            current['value'] = match['value'] ?? match['defaultData'];
        }
        return current;
      }).toList();
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          'This file does not contain usable SmartSpin2k settings. Choose a .ss2k or compatible .json settings file.',
          success: false,
        );
      }
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final existingNames = prefs.getStringList('backups_list') ?? [];
      existingNames.sort();
      if (!context.mounted) return;
      final suggestedName = fileName.replaceFirst(
        RegExp(r'\.(ss2k|json)$', caseSensitive: false),
        '',
      );
      final saveName = await showDialog<String>(
        context: context,
        builder: (_) => SettingsBackupNameDialog(
          title: 'Import from a file',
          description:
              'Add “$fileName” to your saved copies in this app. Your SmartSpin2k stays as it is until you choose to load the settings.',
          actionLabel: 'Import copy',
          initialName: suggestedName,
          existingNames: existingNames,
        ),
      );
      if (saveName == null || !context.mounted) return;

      final saved = await PresetManager.savePreset(
        context,
        deviceData,
        saveName,
        settings: mergedConfig,
        showSuccess: false,
      );
      if (!saved || !context.mounted) return;

      final applyNow = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Copy imported'),
          scrollable: true,
          content: Text(
            '“$saveName” is saved in this app.\n\nLoad it onto your SmartSpin2k now? This replaces the device settings. Your current Wi-Fi name and password will stay the same.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep for later'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Load onto SmartSpin2k'),
            ),
          ],
        ),
      );
      if (applyNow == true && context.mounted) {
        deviceData.customCharacteristic = mergedConfig;
        try {
          await deviceData.saveAllSettings(device);
          if (context.mounted) {
            Snackbar.show(
              ABC.c,
              '“$saveName” loaded onto SmartSpin2k.',
              success: true,
            );
          }
        } catch (e) {
          if (context.mounted) {
            Snackbar.show(
              ABC.c,
              'Copy imported, but could not load it onto SmartSpin2k. Reconnect and try “Load saved settings”.',
              success: false,
            );
          }
        }
      } else if (context.mounted) {
        Snackbar.show(
          ABC.c,
          '“$saveName” saved in this app. Use “Load saved settings” when you need it.',
          success: true,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          'Could not import the settings copy. Please try again.',
          success: false,
        );
      }
    }
  }
}
