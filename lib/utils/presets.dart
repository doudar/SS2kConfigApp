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

import './preset_sharing.dart';

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
              constraints: BoxConstraints(maxHeight: 500),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: presetsList.length,
                separatorBuilder: (context, index) => Divider(height: 1),
                itemBuilder: (context, index) {
                  final presetName = presetsList[index];
                  return ListTile(
                    title: Text(presetName),
                    trailing: IconButton(
                      icon: Icon(Icons.visibility_outlined),
                      tooltip: 'View Details',
                      onPressed: () async {
                        String? presetData = prefs.getString('backup_$presetName');
                        if (presetData != null) {
                          try {
                            List<dynamic> settings = jsonDecode(presetData);
                            await _showPresetDetails(context, presetName, settings);
                          } catch (e) {
                            debugPrint("Error viewing preset: $e");
                          }
                        }
                      },
                    ),
                    onTap: () => Navigator.of(context).pop(presetName),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                child: Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
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
        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 400),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 20),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                  child: Text(
                    'Settings Manager',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),

                _buildSectionHeader(context, "Local Storage"),
                _buildMenuOption(
                  context,
                  icon: Icons.save,
                  title: 'Save to App',
                  subtitle: 'Save current settings to "My Files"',
                  value: 'save',
                ),
                _buildMenuOption(
                  context,
                  icon: Icons.folder_open,
                  title: 'Load from App',
                  subtitle: 'Apply settings from "My Files"',
                  value: 'load',
                ),
                _buildMenuOption(
                  context,
                  icon: Icons.delete_outline,
                  title: 'Manage Files',
                  subtitle: 'Delete presets from "My Files"',
                  value: 'delete',
                ),

                _buildSectionHeader(context, "Sharing"),
                _buildMenuOption(
                  context,
                  icon: Icons.file_download_outlined,
                  title: 'Import File',
                  subtitle: 'Open a .ss2k file from your phone',
                  value: 'import',
                ),
                _buildMenuOption(
                  context,
                  icon: Icons.share_outlined,
                  title: 'Export File',
                  subtitle: 'Share current settings as a file',
                  value: 'export',
                ),

                _buildSectionHeader(context, "Device"),
                 _buildMenuOption(
                  context,
                  icon: Icons.restart_alt,
                  title: 'Reset to Defaults',
                  subtitle: 'Reset device to factory settings',
                  value: 'reset',
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null || !context.mounted) return;

    switch (action) {
      case 'reset':
         bool? confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Reset to Defaults'),
              content: Text('Are you sure you want to reset the device to factory defaults? This cannot be undone.'),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                FilledButton(
                  child: Text('Reset'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            );
          },
        );
        
        if (confirmed == true && context.mounted) {
          try {
            await bleData.resetToDefaults(device);
            // Reconnect logic from resetToDefaults might clear logs/state, wait for a bit
             await Future.delayed(Duration(seconds: 1));
             // Trigger a refresh/connect cycle properly
             await device.connectAndUpdateStream();
             // Reset UI state implicitly through connection change orexplicit snackbar
            Snackbar.show(ABC.c, "SmartSpin2k has been reset to defaults", success: true);
          } catch (e) {
             if (context.mounted) {
               Snackbar.show(ABC.c, prettyException("Reset Failed ", e), success: false);
             }
          }
        }
        break;
      case 'save':
        SharedPreferences prefs = await SharedPreferences.getInstance();
        List<String> existingPresets = prefs.getStringList('backups_list') ?? [];
        existingPresets.sort();

        final nameController = TextEditingController();
        final presetName = await showDialog<String>(
          context: context,
          builder: (BuildContext context) {
            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: Text('Save to My Files'),
                  content: Container(
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: nameController,
                          decoration: InputDecoration(
                            hintText: 'Enter preset name',
                            labelText: 'Preset Name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.settings),
                          ),
                          onChanged: (text) => setState(() {}),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Existing Presets (${existingPresets.length})',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        SizedBox(height: 8),
                        Flexible(
                          child: Container(
                            constraints: BoxConstraints(maxHeight: 200),
                            decoration: BoxDecoration(
                              border: Border.all(color: Theme.of(context).dividerColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: existingPresets.isEmpty
                                ? Center(
                                    child: Text(
                                      'No saved presets',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: existingPresets.length,
                                    separatorBuilder: (context, index) => Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final name = existingPresets[index];
                                      final isSelected = name == nameController.text;
                                      return ListTile(
                                        title: Text(name),
                                        dense: true,
                                        selected: isSelected,
                                        selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2),
                                        onTap: () {
                                          nameController.text = name;
                                          setState(() {});
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      child: Text('Cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    FilledButton(
                      child: Text(existingPresets.contains(nameController.text) ? 'Overwrite' : 'Save'),
                      onPressed: nameController.text.trim().isEmpty
                          ? null
                          : () => Navigator.of(context).pop(nameController.text.trim()),
                    ),
                  ],
                );
              },
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
      case 'export':
        final nameController = TextEditingController();
        final fileName = await showDialog<String>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Export File'),
              content: TextField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: 'Enter file name',
                  labelText: 'File Name',
                  border: OutlineInputBorder(),
                  suffixText: '.ss2k'
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                FilledButton(
                  child: Text('Export'),
                  onPressed: () => Navigator.of(context).pop(nameController.text),
                ),
              ],
            );
          },
        );
        if (fileName != null && fileName.isNotEmpty && context.mounted) {
          await PresetSharing.exportPreset(context, bleData, fileName);
        }
        break;
      case 'import':
        await PresetSharing.importPreset(context, bleData, device);
        break;
    }
  }

  static Future<void> _showPresetDetails(BuildContext context, String name, List<dynamic> settings) async {
    // Filter only items that are settings
    final displaySettings = settings.where((s) => s['isSetting'] == true).toList();
    
    // Sort logic to match main UI or keep raw? Let's just sort alphabetically by name for easy reading
    displaySettings.sort((a, b) => (a['humanReadableName'] ?? '').compareTo(b['humanReadableName'] ?? ''));

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Preset: $name'),
        content: Container(
           width: double.maxFinite,
           constraints: BoxConstraints(maxHeight: 400),
           child: displaySettings.isEmpty ? 
             Center(child: Text("No displayable settings found.")) :
             ListView.separated(
             shrinkWrap: true,
             itemCount: displaySettings.length,
             separatorBuilder: (context, index) => Divider(height: 1),
             itemBuilder: (context, index) {
               final item = displaySettings[index];
               final displayValue = item['value'] ?? item['defaultData'];
               return ListTile(
                 title: Text(item['humanReadableName'] ?? item['vName'] ?? 'Unknown', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                 subtitle: Text(displayValue.toString(), style: TextStyle(fontSize: 13)),
                 dense: true,
                 contentPadding: EdgeInsets.symmetric(horizontal: 4),
               );
             },
           ),
        ),
        actions: [
          TextButton(
            child: Text('Close'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  static Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
      ),
    );
  }

  static Widget _buildMenuOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
  }) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      onTap: () {
        Navigator.of(context).pop(value);
      },
    );
  }
}
