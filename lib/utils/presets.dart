/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import './bledata.dart';
import './snackbar.dart';
import './extra.dart';

class PresetManager {
  static Future<void> savePreset(BuildContext context, BLEData bleData, String presetName) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> presetsList = prefs.getStringList('backups_list') ?? [];
      
      String presetKey = 'backup_$presetName';
      await prefs.setString(presetKey, jsonEncode(bleData.customCharacteristic));
      
      if (!presetsList.contains(presetName)) {
        presetsList.add(presetName);
        await prefs.setStringList('backups_list', presetsList);
      }
      
      if (context.mounted) {
        Snackbar.show(ABC.c, "Preset '$presetName' saved successfully", success: true);
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(ABC.c, prettyException("Save Preset Failed ", e), success: false);
      }
    }
  }

  static Future<void> loadPreset(BuildContext context, BLEData bleData, BluetoothDevice device) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> presetsList = prefs.getStringList('backups_list') ?? [];

      if (presetsList.isEmpty) {
        if (context.mounted) {
          Snackbar.show(ABC.c, "No presets found", success: false);
        }
        return;
      }

      if (!context.mounted) return;
      
      String? selectedPreset = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Select Preset'),
            content: Container(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: presetsList.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(presetsList[index]),
                    onTap: () => Navigator.of(context).pop(presetsList[index]),
                  );
                },
              ),
            ),
          );
        },
      );

      if (selectedPreset == null || !context.mounted) return;

      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Confirm Load'),
            content: Text('This will overwrite your current settings.'),
            actions: <Widget>[
              TextButton(
                child: Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                child: Text('Okay'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          );
        },
      );

      if (confirmed != true || !context.mounted) return;

      String? presetData = prefs.getString('backup_$selectedPreset');
      if (presetData == null) {
        if (context.mounted) {
          Snackbar.show(ABC.c, "Preset not found", success: false);
        }
        return;
      }

      bleData.customCharacteristic = jsonDecode(presetData);
      await bleData.saveAllSettings(device);
      
      if (context.mounted) {
        Snackbar.show(ABC.c, "Preset loaded and saved to device", success: true);
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(ABC.c, prettyException("Load preset failed", e), success: false);
      }
    }
  }

  static Future<void> deletePreset(BuildContext context) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> presetsList = prefs.getStringList('backups_list') ?? [];

      if (presetsList.isEmpty) {
        if (context.mounted) {
          Snackbar.show(ABC.c, "No presets found", success: false);
        }
        return;
      }

      if (!context.mounted) return;
      
      String? selectedPreset = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Select Preset to Delete'),
            content: Container(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: presetsList.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(presetsList[index]),
                    onTap: () => Navigator.of(context).pop(presetsList[index]),
                  );
                },
              ),
            ),
          );
        },
      );

      if (selectedPreset == null || !context.mounted) return;

      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Confirm Delete'),
            content: Text('Are you sure you want to delete this preset?'),
            actions: <Widget>[
              TextButton(
                child: Text('No'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                child: Text('Yes'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          );
        },
      );

      if (confirmed != true || !context.mounted) return;

      String presetKey = 'backup_$selectedPreset';
      await prefs.remove(presetKey);
      
      presetsList.remove(selectedPreset);
      await prefs.setStringList('backups_list', presetsList);
      
      if (context.mounted) {
        Snackbar.show(ABC.c, "Preset '$selectedPreset' deleted successfully", success: true);
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(ABC.c, prettyException("Delete preset failed", e), success: false);
      }
    }
  }

  static Future<void> showPresetsMenu(BuildContext context, BLEData bleData, BluetoothDevice device) async {
    if (!context.mounted) return;

    String? action = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Presets Menu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.save),
                title: Text('Save Preset'),
                onTap: () {
                  Navigator.of(context).pop('save');
                },
              ),
              ListTile(
                leading: Icon(Icons.file_upload),
                title: Text('Load Preset'),
                onTap: () {
                  Navigator.of(context).pop('load');
                },
              ),
              ListTile(
                leading: Icon(Icons.delete),
                title: Text('Delete Preset'),
                onTap: () {
                  Navigator.of(context).pop('delete');
                },
              ),
            ],
          ),
        );
      },
    );

    if (action == null || !context.mounted) return;

    switch (action) {
      case 'save':
        final nameController = TextEditingController();
        final presetName = await showDialog<String>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Save Preset'),
              content: TextField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: 'Enter preset name',
                  labelText: 'Preset Name',
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: Text('Save'),
                  onPressed: () => Navigator.of(context).pop(nameController.text),
                ),
              ],
            );
          },
        );
        if (presetName != null && presetName.isNotEmpty && context.mounted) {
          await savePreset(context, bleData, presetName);
        }
        break;
      case 'load':
        await loadPreset(context, bleData, device);
        break;
      case 'delete':
        await deletePreset(context);
        break;
    }
  }
}
