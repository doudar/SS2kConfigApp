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
import './device_data.dart';
import './snackbar.dart';
import './extra.dart';
import './constants.dart';

import './preset_sharing.dart';
import '../widgets/settings_backup_name_dialog.dart';

class PresetManager {
  static Future<bool> savePreset(
    BuildContext context,
    DeviceData deviceData,
    String presetName, {
    List<Map<String, dynamic>>? settings,
    bool showSuccess = true,
  }) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> presetsList = prefs.getStringList('backups_list') ?? [];

      String presetKey = 'backup_$presetName';

      // Filter out non-encodable objects like SettingType enum and only save vName/value
      List<Map<String, dynamic>> saveableData = [];
      for (var item in settings ?? deviceData.customCharacteristic) {
        if (item.containsKey('vName') && item.containsKey('value')) {
          saveableData.add({'vName': item['vName'], 'value': item['value']});
        }
      }

      if (!await prefs.setString(presetKey, jsonEncode(saveableData))) {
        throw StateError('The app could not store this copy.');
      }

      if (!presetsList.contains(presetName)) {
        presetsList.add(presetName);
        if (!await prefs.setStringList('backups_list', presetsList)) {
          throw StateError('The app could not update the saved copies list.');
        }
      }

      if (showSuccess && context.mounted) {
        Snackbar.show(
          ABC.c,
          '“$presetName” saved in this app. SmartSpin2k settings are unchanged.',
          success: true,
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          prettyException('Could not save the settings copy. ', e),
          success: false,
        );
      }
      return false;
    }
  }

  static Future<void> loadPreset(
    BuildContext context,
    DeviceData deviceData,
    BluetoothDevice device,
  ) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> presetsList = prefs.getStringList('backups_list') ?? [];

      if (presetsList.isEmpty) {
        if (context.mounted) {
          await _showNoSavedCopies(context);
        }
        return;
      }

      if (!context.mounted) return;

      String? selectedPreset = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Load saved settings'),
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
                    leading: const Icon(Icons.restore),
                    title: Text(presetName),
                    subtitle: const Text('Choose this copy to load'),
                    trailing: IconButton(
                      icon: Icon(Icons.visibility_outlined),
                      tooltip: 'View saved settings',
                      onPressed: () async {
                        String? presetData = prefs.getString(
                          'backup_$presetName',
                        );
                        if (presetData != null) {
                          try {
                            List<dynamic> settings = jsonDecode(presetData);
                            await _showPresetDetails(
                              context,
                              presetName,
                              settings,
                              deviceData,
                            );
                          } catch (e) {
                            Snackbar.show(
                              ABC.c,
                              'Could not read this saved copy.',
                              success: false,
                            );
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
            title: Text('Load “$selectedPreset”?'),
            content: Text(
              'This will replace the settings on your SmartSpin2k with this saved copy, including any saved Wi-Fi details.\n\nSave a copy of your current settings first if you want to keep them.',
            ),
            scrollable: true,
            actions: <Widget>[
              TextButton(
                child: Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              FilledButton(
                child: Text('Load onto SmartSpin2k'),
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
          Snackbar.show(
            ABC.c,
            'This saved copy could not be found. Save a new copy or import a settings file.',
            success: false,
          );
        }
        return;
      }

      // Parse the preset data
      List<dynamic> loadedSettings = jsonDecode(presetData);

      // Update existing settings with loaded values only
      // This preserves structural data like SettingType Enums which are not in the JSON
      for (var loadedItem in loadedSettings) {
        if (loadedItem is Map &&
            loadedItem.containsKey("vName") &&
            loadedItem.containsKey("value")) {
          // Find matching item in current configuration
          try {
            var matchingItems = deviceData.customCharacteristic.where(
              (item) => item["vName"] == loadedItem["vName"],
            );

            if (matchingItems.isNotEmpty) {
              var currentItem = matchingItems.first;
              // Only update the value
              currentItem["value"] = loadedItem["value"];
            }
          } catch (e) {
            print("Error updating setting ${loadedItem["vName"]}: $e");
          }
        }
      }

      await deviceData.saveAllSettings(device);

      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          '“$selectedPreset” loaded onto SmartSpin2k.',
          success: true,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          prettyException('Could not load settings onto SmartSpin2k. ', e),
          success: false,
        );
      }
    }
  }

  static Future<void> deletePreset(BuildContext context) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();

      while (context.mounted) {
        List<String> presetsList = prefs.getStringList('backups_list') ?? [];

        if (presetsList.isEmpty) {
          if (context.mounted) {
            await _showNoSavedCopies(context);
          }
          return;
        }

        String? selectedPreset = await showDialog<String>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Delete a saved copy'),
              content: Container(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: presetsList.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: Text(presetsList[index]),
                      onTap: () =>
                          Navigator.of(context).pop(presetsList[index]),
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
            );
          },
        );

        if (selectedPreset == null || !context.mounted) return;

        bool? confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Delete “$selectedPreset”?'),
              content: Text(
                'This removes the saved copy from this app. Your SmartSpin2k settings and exported files will stay as they are.',
              ),
              scrollable: true,
              actions: <Widget>[
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  child: Text('Delete copy'),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            );
          },
        );

        if (confirmed != true || !context.mounted) continue;

        String presetKey = 'backup_$selectedPreset';
        await prefs.remove(presetKey);

        presetsList.remove(selectedPreset);
        await prefs.setStringList('backups_list', presetsList);

        if (context.mounted) {
          Snackbar.show(
            ABC.c,
            '“$selectedPreset” deleted from this app.',
            success: true,
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          prettyException('Could not delete the saved copy. ', e),
          success: false,
        );
      }
    }
  }

  static Future<void> showPresetsMenu(
    BuildContext context,
    DeviceData deviceData,
    BluetoothDevice device,
  ) async {
    if (!context.mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Save & restore settings',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: Text(
                        'Keep a copy of your SmartSpin2k setup, restore one, or move settings between devices.',
                      ),
                    ),
                    _buildSectionHeader(context, 'Saved in this app'),
                    _buildMenuOption(
                      context,
                      icon: Icons.bookmark_add_outlined,
                      title: 'Save a copy',
                      subtitle:
                          'Keep your current settings in this app for later.',
                      value: 'save',
                    ),
                    _buildMenuOption(
                      context,
                      icon: Icons.restore,
                      title: 'Load saved settings',
                      subtitle: 'Put a saved copy onto your SmartSpin2k.',
                      value: 'load',
                    ),
                    _buildMenuOption(
                      context,
                      icon: Icons.delete_outline,
                      title: 'Delete a saved copy',
                      subtitle: 'Remove a copy from this app.',
                      value: 'delete',
                    ),
                    const Divider(indent: 24, endIndent: 24),
                    _buildSectionHeader(context, 'Settings files'),
                    _buildMenuOption(
                      context,
                      icon: Icons.file_open_outlined,
                      title: 'Import from a file',
                      subtitle:
                          'Add a .ss2k or .json settings file to your saved copies. Choose whether to load it next.',
                      value: 'import',
                    ),
                    _buildMenuOption(
                      context,
                      icon: Icons.ios_share,
                      title: 'Export to a file',
                      subtitle:
                          'Create a file of your current settings to save elsewhere or share.',
                      value: 'export',
                    ),
                    const Divider(indent: 24, endIndent: 24),
                    _buildSectionHeader(context, 'Start over'),
                    _buildMenuOption(
                      context,
                      icon: Icons.restart_alt,
                      title: 'Factory reset SmartSpin2k',
                      subtitle:
                          'Replace the device settings with factory defaults.',
                      value: 'reset',
                      destructive: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (action == null || !context.mounted) return;

    switch (action) {
      case 'reset':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Factory reset SmartSpin2k?'),
            scrollable: true,
            content: const Text(
              'This replaces the settings on your SmartSpin2k with factory defaults. Your saved copies in this app will stay available.\n\nSave a copy of your current settings first if you want to restore them later.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Reset SmartSpin2k'),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          try {
            await deviceData.resetToDefaults(device);
            await Future.delayed(const Duration(seconds: 1));
            await device.connectAndUpdateStream();
            if (context.mounted) {
              Snackbar.show(
                ABC.c,
                'SmartSpin2k reset to factory settings.',
                success: true,
              );
            }
          } catch (e) {
            if (context.mounted) {
              Snackbar.show(
                ABC.c,
                prettyException('Could not reset SmartSpin2k. ', e),
                success: false,
              );
            }
          }
        }
        break;
      case 'save':
        final prefs = await SharedPreferences.getInstance();
        final existingPresets = prefs.getStringList('backups_list') ?? [];
        existingPresets.sort();
        if (!context.mounted) return;
        final presetName = await showDialog<String>(
          context: context,
          builder: (_) => SettingsBackupNameDialog(
            title: 'Save a copy',
            description:
                'Save your current SmartSpin2k settings, including Wi-Fi details, in this app. Use “Load saved settings” to restore them later.',
            actionLabel: 'Save copy',
            existingNames: existingPresets,
          ),
        );
        if (presetName != null && context.mounted) {
          await savePreset(context, deviceData, presetName);
        }
        break;
      case 'load':
        await loadPreset(context, deviceData, device);
        break;
      case 'delete':
        await deletePreset(context);
        break;
      case 'export':
        final fileName = await showDialog<String>(
          context: context,
          builder: (_) => const SettingsBackupNameDialog(
            title: 'Export to a file',
            description:
                'Create a .ss2k file from the settings currently on your SmartSpin2k. Next, choose where to save or share it.\n\nYour Wi-Fi name and password are left out.',
            actionLabel: 'Choose where to save or share',
            initialName: 'My bike setup',
            isExport: true,
          ),
        );
        if (fileName != null && context.mounted) {
          await PresetSharing.exportPreset(context, deviceData, fileName);
        }
        break;
      case 'import':
        await PresetSharing.importPreset(context, deviceData, device);
        break;
    }
  }

  static Future<void> _showNoSavedCopies(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No saved copies yet'),
        scrollable: true,
        content: const Text(
          'Choose “Save a copy” to keep your current SmartSpin2k settings, or “Import from a file” to add settings saved elsewhere.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showPresetDetails(
    BuildContext context,
    String name,
    List<dynamic> savedSettings,
    DeviceData deviceData,
  ) async {
    List<Map<String, dynamic>> displaySettings = [];

    for (var savedItem in savedSettings) {
      if (savedItem is Map && savedItem.containsKey('vName')) {
        // Find matching current config to get readable name
        var matchingItems = deviceData.customCharacteristic.where(
          (c) => c['vName'] == savedItem['vName'],
        );
        var currentItem = matchingItems.isNotEmpty ? matchingItems.first : null;

        if (currentItem != null && currentItem['isSetting'] == true) {
          displaySettings.add({
            'humanReadableName': currentItem['humanReadableName'],
            'vName': savedItem['vName'],
            'value': savedItem['value'],
          });
        }
      }
    }

    // Sort logic to match main UI or keep raw? Let's just sort alphabetically by name for easy reading
    displaySettings.sort(
      (a, b) => (a['humanReadableName'] ?? '').compareTo(
        b['humanReadableName'] ?? '',
      ),
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Saved settings: $name'),
        content: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(maxHeight: 400),
          child: displaySettings.isEmpty
              ? Center(child: Text('This copy has no settings to preview.'))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: displaySettings.length,
                  separatorBuilder: (context, index) => Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = displaySettings[index];
                    final displayValue = (item['vName'] == passwordVname)
                        ? "**********"
                        : item['value'];
                    return ListTile(
                      title: Text(
                        item['humanReadableName'] ?? item['vName'] ?? 'Unknown',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        displayValue.toString(),
                        style: TextStyle(fontSize: 13),
                      ),
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
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
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
    bool destructive = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: destructive
              ? colors.errorContainer
              : colors.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: destructive
              ? colors.onErrorContainer
              : colors.onSecondaryContainer,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: destructive ? colors.error : null,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(subtitle),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: () {
        Navigator.of(context).pop(value);
      },
    );
  }
}
