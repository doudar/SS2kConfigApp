/*
 * Copyright (C) 2020  Anthony Doud
 * All rights reserved
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import './bledata.dart';
import './snackbar.dart';
import './power_table_sharing.dart';
import './constants.dart';

class PowerTableManager {
  static const String _powerTablesListKey = 'power_tables_list';
  static const String _powerTablePrefix = 'power_table_';

  // Check if a table name already exists
  static Future<bool> isTableNameExists(String tableName) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> tablesList = prefs.getStringList(_powerTablesListKey) ?? [];
    return tablesList.contains(tableName);
  }

  // Generate test data for the power table
  static Future<void> loadTestData(
    BuildContext context,
    BLEData bleData,
    BluetoothDevice device,
  ) async {
    bleData.isPowerTableTransferInProgress = true;
    try {
      // Clear existing data
      for (int i = 0; i < bleData.powerTableData.length; i++) {
        for (int j = 0; j < bleData.powerTableData[i].length; j++) {
          bleData.powerTableData[i][j] = null;
        }
      }

      // Cadence values from 60 to 105 RPM (10 rows)
      final List<int> cadences = [60, 65, 70, 75, 80, 85, 90, 95, 100, 105];

      // For each cadence row
      for (int rowIndex = 0; rowIndex < cadences.length; rowIndex++) {
        int cadence = cadences[rowIndex];
        List<int> rowValue = [];

        // For each power column (0-1000W in 30W increments)
        for (int col = 0; col < 38; col++) {
          int targetWatts = col * 30;

          // Calculate resistance based on cadence and target watts
          // Higher resistance for lower cadence to achieve same watts
          // Base formula: resistance = (watts * cadenceAdjustment) / cadence
          double cadenceAdjustment = 100.0 / cadence; // Adjustment factor
          int resistance = ((targetWatts * cadenceAdjustment) * 1.5).round();

          // Limit resistance to reasonable range (0-6000)
          resistance = resistance.clamp(0, 6000);

          bleData.powerTableData[rowIndex][col] = resistance;

          // Convert to bytes for transmission
          final bytes = Uint8List(2)
            ..buffer.asByteData().setInt16(0, resistance, Endian.little);
          rowValue.addAll(bytes);
        }

        // Send the row to the device
        List<int> command = [0x02, 0x27, rowIndex, ...rowValue];

        try {
          if (!bleData.isTransportActive) {
            throw Exception("Device transport disconnected");
          }
          await bleData.writeCustomCharacteristic(device, command);
          // Preserve the existing pacing after the acknowledged response.
          await Future.delayed(Duration(milliseconds: 500));
        } catch (e) {
          if (context.mounted) {
            Snackbar.show(
              ABC.c,
              "Failed to send test data row ${rowIndex + 1}: $e",
              success: false,
            );
          }
          return;
        }
      }

      if (context.mounted) {
        Snackbar.show(ABC.c, "Test data loaded successfully", success: true);
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          prettyException("Load test data failed", e),
          success: false,
        );
      }
    } finally {
      bleData.isPowerTableTransferInProgress = false;
    }
  }

  static Future<void> savePowerTable(
    BuildContext context,
    BLEData bleData,
    String tableName,
  ) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> tablesList = prefs.getStringList(_powerTablesListKey) ?? [];

      // Get current HMax value from the device
      String hMaxValue = bleData.getVnameValue(BLE_hMaxVname);

      // Create a data structure that includes both power table and HMax
      Map<String, dynamic> tableData = {
        'powerTable': bleData.powerTableData,
        'hMax': hMaxValue != noFirmSupport ? hMaxValue : null,
      };

      // Save the power table data with HMax
      String tableKey = _powerTablePrefix + tableName;
      await prefs.setString(tableKey, jsonEncode(tableData));

      // Add to tables list if not already present
      if (!tablesList.contains(tableName)) {
        tablesList.add(tableName);
        await prefs.setStringList(_powerTablesListKey, tablesList);
      }

      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          "Power table '$tableName' saved successfully",
          success: true,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          prettyException("Save power table failed ", e),
          success: false,
        );
      }
    }
  }

  // Send power table data to device
  static Future<bool> sendPowerTableToDevice(
    BuildContext context,
    BLEData bleData,
    BluetoothDevice device, {
    String? hMaxValue,
  }) async {
    if (!bleData.isTransportActive) {
      if (context.mounted) {
        Snackbar.show(ABC.c, "Device not connected", success: false);
      }
      return false;
    }

    // Read callbacks update powerTableData in place. Preserve the table chosen
    // by the user so a periodic read of an as-yet-unsent firmware row cannot
    // erase the source data halfway through this transfer.
    final rowsToSend = bleData.powerTableData
        .map((row) => List<int?>.from(row))
        .toList(growable: false);
    bleData.isPowerTableTransferInProgress = true;
    try {
      // Send each row of the power table separately
      const int intMinValue = -32768; // INT16_MIN for missing values

      for (int rowIndex = 0; rowIndex < rowsToSend.length; rowIndex++) {
        List<int?> row = rowsToSend[rowIndex];
        List<int> rowValue = [];

        // Convert each entry in the row to its little-endian byte representation
        for (int? entry in row) {
          int valueToConvert = entry ?? intMinValue;
          final bytes = Uint8List(2)
            ..buffer.asByteData().setInt16(0, valueToConvert, Endian.little);
          rowValue.addAll(bytes);
        }

        // Combine command (0x02), reference (0x27), row index, and resistance values
        List<int> command = [0x02, 0x27, rowIndex, ...rowValue];

        try {
          if (!bleData.isTransportActive) {
            throw Exception("Device transport disconnected");
          }
          await bleData.writeCustomCharacteristic(device, command);
          // Preserve the existing pacing after the acknowledged response.
          await Future.delayed(Duration(milliseconds: 100));
        } catch (e) {
          if (context.mounted) {
            Snackbar.show(
              ABC.c,
              "Failed to send row ${rowIndex + 1}: $e",
              success: false,
            );
          }
          return false;
        }
      }

      // Send HMax to the device if available
      if (hMaxValue != null && hMaxValue != noFirmSupport) {
        try {
          // Find HMax in custom characteristic framework and write to device
          for (var c in bleData.customCharacteristic) {
            if (c["vName"] == BLE_hMaxVname) {
              await bleData.writeToSS2k(device, c, s: hMaxValue);
              break;
            }
          }
        } catch (e) {
          if (context.mounted) {
            Snackbar.show(ABC.c, "Failed to set HMax: $e", success: false);
          }
          // Continue even if HMax setting fails, as the power table itself was sent successfully
        }
      }

      // Read every row back while periodic chart polling is paused. Besides
      // verifying the device accepted the transfer, these responses drive the
      // normal decoder/UI notification path with authoritative table data.
      for (int rowIndex = 0; rowIndex < rowsToSend.length; rowIndex++) {
        await bleData.requestSetting(
          device,
          powerTableDataVname,
          extraByte: rowIndex,
        );
      }

      final mismatch = _firstMismatchedRow(rowsToSend, bleData.powerTableData);
      if (mismatch != null) {
        print('[PowerTable] Readback mismatch on row $mismatch after transfer');
        if (context.mounted) {
          Snackbar.show(
            ABC.c,
            'Power table verification failed on row ${mismatch + 1}',
            success: false,
          );
        }
        return false;
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          prettyException("Failed to send power table", e),
          success: false,
        );
      }
      return false;
    } finally {
      bleData.isPowerTableTransferInProgress = false;
    }
  }

  static int? _firstMismatchedRow(
    List<List<int?>> expected,
    List<List<int?>> actual,
  ) {
    if (expected.length != actual.length) return 0;
    for (var rowIndex = 0; rowIndex < expected.length; rowIndex++) {
      final expectedRow = expected[rowIndex];
      final actualRow = actual[rowIndex];
      if (expectedRow.length != actualRow.length) return rowIndex;
      for (var column = 0; column < expectedRow.length; column++) {
        if (expectedRow[column] != actualRow[column]) return rowIndex;
      }
    }
    return null;
  }

  static Future<void> loadPowerTable(
    BuildContext context,
    BLEData bleData,
    BluetoothDevice device,
  ) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> tablesList = prefs.getStringList(_powerTablesListKey) ?? [];
      tablesList.sort();

      if (tablesList.isEmpty) {
        if (context.mounted) {
          Snackbar.show(ABC.c, "No saved power tables found", success: false);
        }
        return;
      }

      if (!context.mounted) return;

      String? selectedTable = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Load from My Files'),
            content: Container(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select a file to load:',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  SizedBox(height: 12),
                  Flexible(
                    child: Container(
                      constraints: BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: tablesList.length,
                        separatorBuilder: (context, index) =>
                            Divider(height: 1),
                        itemBuilder: (context, index) {
                          return ListTile(
                            leading: Icon(Icons.file_present),
                            title: Text(tablesList[index]),
                            onTap: () =>
                                Navigator.of(context).pop(tablesList[index]),
                          );
                        },
                      ),
                    ),
                  ),
                ],
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

      if (selectedTable == null || !context.mounted) return;

      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Confirm Load'),
            content: Text('This will overwrite your current power table.'),
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

      String? tableData = prefs.getString(_powerTablePrefix + selectedTable);
      if (tableData == null) {
        if (context.mounted) {
          Snackbar.show(ABC.c, "Power table not found", success: false);
        }
        return;
      }

      // Parse saved data
      dynamic decodedData = jsonDecode(tableData);
      String? hMaxValue;
      List<dynamic> jsonPowerTableData;

      // Handle both old format (just array) and new format (object with powerTable and hMax)
      if (decodedData is Map) {
        jsonPowerTableData = decodedData['powerTable'] as List<dynamic>;
        hMaxValue = decodedData['hMax'] as String?;
      } else {
        // Legacy format - just an array of power table data
        jsonPowerTableData = decodedData as List<dynamic>;
      }

      // Load the power table data
      bleData.powerTableData = List<List<int?>>.from(
        jsonPowerTableData.map(
          (row) => List<int?>.from(row.map((value) => value as int?)),
        ),
      );

      // Send power table data to device
      bool success = await sendPowerTableToDevice(
        context,
        bleData,
        device,
        hMaxValue: hMaxValue,
      );

      if (success && context.mounted) {
        Snackbar.show(
          ABC.c,
          "Power table loaded and sent to device",
          success: true,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          prettyException("Load power table failed", e),
          success: false,
        );
      }
    }
  }

  static Future<void> deletePowerTable(BuildContext context) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> tablesList = prefs.getStringList(_powerTablesListKey) ?? [];
      tablesList.sort();

      if (tablesList.isEmpty) {
        if (context.mounted) {
          Snackbar.show(ABC.c, "No saved power tables found", success: false);
        }
        return;
      }

      if (!context.mounted) return;

      String? selectedTable = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Delete from My Files'),
            content: Container(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select a file to delete:',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  SizedBox(height: 12),
                  Flexible(
                    child: Container(
                      constraints: BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: tablesList.length,
                        separatorBuilder: (context, index) =>
                            Divider(height: 1),
                        itemBuilder: (context, index) {
                          return ListTile(
                            leading: Icon(
                              Icons.delete_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            title: Text(tablesList[index]),
                            onTap: () =>
                                Navigator.of(context).pop(tablesList[index]),
                          );
                        },
                      ),
                    ),
                  ),
                ],
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

      if (selectedTable == null || !context.mounted) return;

      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Confirm Delete'),
            content: Text('Are you sure you want to delete this power table?'),
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

      String tableKey = _powerTablePrefix + selectedTable;
      await prefs.remove(tableKey);

      tablesList.remove(selectedTable);
      await prefs.setStringList(_powerTablesListKey, tablesList);

      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          "Power table '$selectedTable' deleted successfully",
          success: true,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(
          ABC.c,
          prettyException("Delete power table failed", e),
          success: false,
        );
      }
    }
  }

  static Future<void> showPowerTableMenu(
    BuildContext context,
    BLEData bleData,
    BluetoothDevice device,
  ) async {
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
                    'Power Table Management',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _buildSectionHeader(context, "Local Storage"),
                _buildMenuOption(
                  context,
                  icon: Icons.save,
                  title: 'Save to phone',
                  subtitle: 'Save current table to "My Files"',
                  value: 'save',
                ),
                _buildMenuOption(
                  context,
                  icon: Icons.folder_open,
                  title: 'Load to SmartSpin2k',
                  subtitle: 'Open a table from "My Files"',
                  value: 'load',
                ),
                _buildMenuOption(
                  context,
                  icon: Icons.delete_outline,
                  title: 'Manage Files',
                  subtitle: 'Delete tables from "My Files"',
                  value: 'delete',
                ),

                _buildSectionHeader(context, "Sharing"),
                _buildMenuOption(
                  context,
                  icon: Icons.file_download_outlined,
                  title: 'Import File',
                  subtitle: 'Open a .ptab file from your phone',
                  value: 'import',
                ),
                _buildMenuOption(
                  context,
                  icon: Icons.share_outlined,
                  title: 'Export File',
                  subtitle: 'Share current table as a .ptab file',
                  value: 'export',
                ),

                _buildSectionHeader(context, "Device Actions"),
                _buildMenuOption(
                  context,
                  icon: Icons.refresh,
                  title: 'Clear Active Table',
                  subtitle:
                      'Reset the power table and deactivate homing on the SmartSpin2k',
                  value: 'clear',
                ),
                _buildMenuOption(
                  context,
                  icon: Icons.science,
                  title: 'Generate Test Data',
                  subtitle: 'Create a linear power curve and upload to device',
                  value: 'test',
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null || !context.mounted) return;

    switch (action) {
      case 'clear':
        await bleData.resetPowerTable(device);
        break;
      case 'save':
        SharedPreferences prefs = await SharedPreferences.getInstance();
        List<String> existingTables =
            prefs.getStringList(_powerTablesListKey) ?? [];
        existingTables.sort();

        final nameController = TextEditingController();
        final tableName = await showDialog<String>(
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
                            hintText: 'Enter file name',
                            labelText: 'File Name',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.description),
                          ),
                          onChanged: (text) => setState(() {}),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Existing Files (${existingTables.length})',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        SizedBox(height: 8),
                        Flexible(
                          child: Container(
                            constraints: BoxConstraints(maxHeight: 200),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: existingTables.isEmpty
                                ? Center(
                                    child: Text(
                                      'No saved files',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: existingTables.length,
                                    separatorBuilder: (context, index) =>
                                        Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final name = existingTables[index];
                                      final isSelected =
                                          name == nameController.text;
                                      return ListTile(
                                        title: Text(name),
                                        dense: true,
                                        selected: isSelected,
                                        selectedTileColor: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withValues(alpha: 0.2),
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
                      child: Text(
                        existingTables.contains(nameController.text)
                            ? 'Overwrite'
                            : 'Save',
                      ),
                      onPressed: nameController.text.trim().isEmpty
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(nameController.text.trim()),
                    ),
                  ],
                );
              },
            );
          },
        );
        if (tableName != null && tableName.isNotEmpty && context.mounted) {
          await savePowerTable(context, bleData, tableName);
        }
        break;
      case 'load':
        await loadPowerTable(context, bleData, device);
        break;
      case 'delete':
        await deletePowerTable(context);
        break;
      case 'test':
        loadTestData(context, bleData, device);
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
                  suffixText: '.json',
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                FilledButton(
                  child: Text('Export'),
                  onPressed: () =>
                      Navigator.of(context).pop(nameController.text),
                ),
              ],
            );
          },
        );
        if (fileName != null && fileName.isNotEmpty && context.mounted) {
          await PowerTableSharing.exportPowerTable(context, bleData, fileName);
        }
        break;
      case 'import':
        await PowerTableSharing.importPowerTable(context, bleData, device);
        break;
    }
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
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      onTap: () {
        Navigator.of(context).pop(value);
      },
    );
  }
}
