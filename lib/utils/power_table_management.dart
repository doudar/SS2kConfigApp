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
  static void loadTestData(BuildContext context, BLEData bleData, BluetoothDevice device) async {
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
          final bytes = Uint8List(2)..buffer.asByteData().setInt16(0, resistance, Endian.little);
          rowValue.addAll(bytes);
        }

        // Send the row to the device
        List<int> command = [0x02, 0x27, rowIndex, ...rowValue];

        try {
          if (!device.isConnected) {
            throw Exception("Device not connected");
          }
          bleData.write(device, command);
          // Add a small delay between rows
          await Future.delayed(Duration(milliseconds: 500));
        } catch (e) {
          if (context.mounted) {
            Snackbar.show(ABC.c, "Failed to send test data row ${rowIndex + 1}: $e", success: false);
          }
          return;
        }
      }

      if (context.mounted) {
        Snackbar.show(ABC.c, "Test data loaded successfully", success: true);
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(ABC.c, prettyException("Load test data failed", e), success: false);
      }
    }
  }

  static Future<void> savePowerTable(BuildContext context, BLEData bleData, String tableName) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> tablesList = prefs.getStringList(_powerTablesListKey) ?? [];

      // Get current HMax value from the device
      String hMaxValue = bleData.getVnameValue(BLE_hMaxVname);
      
      // Create a data structure that includes both power table and HMax
      Map<String, dynamic> tableData = {
        'powerTable': bleData.powerTableData,
        'hMax': hMaxValue != noFirmSupport ? hMaxValue : null
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
        Snackbar.show(ABC.c, "Power table '$tableName' saved successfully", success: true);
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(ABC.c, prettyException("Save power table failed ", e), success: false);
      }
    }
  }

  // Send power table data to device
  static Future<bool> sendPowerTableToDevice(BuildContext context, BLEData bleData, BluetoothDevice device, {String? hMaxValue}) async {
    try {
      // Send each row of the power table separately
      const int intMinValue = -32768; // INT16_MIN for missing values

      for (int rowIndex = 0; rowIndex < bleData.powerTableData.length; rowIndex++) {
        List<int?> row = bleData.powerTableData[rowIndex];
        List<int> rowValue = [];

        // Convert each entry in the row to its little-endian byte representation
        for (int? entry in row) {
          int valueToConvert = entry ?? intMinValue;
          final bytes = Uint8List(2)..buffer.asByteData().setInt16(0, valueToConvert, Endian.little);
          rowValue.addAll(bytes);
        }

        // Combine command (0x02), reference (0x27), row index, and resistance values
        List<int> command = [0x02, 0x27, rowIndex, ...rowValue];

        try {
          if (!device.isConnected) {
            throw Exception("Device not connected");
          }
          bleData.write(device, command);
          // Add a small delay between rows to prevent overwhelming the device
          await Future.delayed(Duration(milliseconds: 100));
        } catch (e) {
          if (context.mounted) {
            Snackbar.show(ABC.c, "Failed to send row ${rowIndex + 1}: $e", success: false);
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
              bleData.writeToSS2k(device, c, s: hMaxValue);
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
      
      return true;
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(ABC.c, prettyException("Failed to send power table", e), success: false);
      }
      return false;
    }
  }

  static Future<void> loadPowerTable(BuildContext context, BLEData bleData, BluetoothDevice device) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> tablesList = prefs.getStringList(_powerTablesListKey) ?? [];

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
            title: Text('Select Power Table'),
            content: Container(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tablesList.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(tablesList[index]),
                    onTap: () => Navigator.of(context).pop(tablesList[index]),
                  );
                },
              ),
            ),
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
        jsonPowerTableData.map((row) => List<int?>.from(row.map((value) => value as int?))),
      );

      // Send power table data to device
      bool success = await sendPowerTableToDevice(context, bleData, device, hMaxValue: hMaxValue);

      if (success && context.mounted) {
        Snackbar.show(ABC.c, "Power table loaded and sent to device", success: true);
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(ABC.c, prettyException("Load power table failed", e), success: false);
      }
    }
  }

  static Future<void> deletePowerTable(BuildContext context) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> tablesList = prefs.getStringList(_powerTablesListKey) ?? [];

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
            title: Text('Select Power Table to Delete'),
            content: Container(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tablesList.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(tablesList[index]),
                    onTap: () => Navigator.of(context).pop(tablesList[index]),
                  );
                },
              ),
            ),
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
        Snackbar.show(ABC.c, "Power table '$selectedTable' deleted successfully", success: true);
      }
    } catch (e) {
      if (context.mounted) {
        Snackbar.show(ABC.c, prettyException("Delete power table failed", e), success: false);
      }
    }
  }

  static Future<void> showPowerTableMenu(BuildContext context, BLEData bleData, BluetoothDevice device) async {
    if (!context.mounted) return;

    String? action = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Manage Power Table'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.clear),
                title: Text('Clear Active PowerTable'),
                onTap: () {
                  Navigator.of(context).pop('clear');
                },
              ),
              ListTile(
                leading: Icon(Icons.save),
                title: Text('Save PowerTable'),
                onTap: () {
                  Navigator.of(context).pop('save');
                },
              ),
              ListTile(
                leading: Icon(Icons.file_upload),
                title: Text('Load PowerTable'),
                onTap: () {
                  Navigator.of(context).pop('load');
                },
              ),
              ListTile(
                leading: Icon(Icons.delete),
                title: Text('Delete PowerTable'),
                onTap: () {
                  Navigator.of(context).pop('delete');
                },
              ),
              ListTile(
                leading: Icon(Icons.share),
                title: Text('Export PowerTable'),
                onTap: () {
                  Navigator.of(context).pop('export');
                },
              ),
              ListTile(
                leading: Icon(Icons.file_download),
                title: Text('Import PowerTable'),
                onTap: () {
                  Navigator.of(context).pop('import');
                },
              ),
              ListTile(
                leading: Icon(Icons.science),
                title: Text('Load Test Data'),
                onTap: () {
                  Navigator.of(context).pop('test');
                },
              ),
            ],
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
        final nameController = TextEditingController();
        final tableName = await showDialog<String>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Save Power Table'),
              content: TextField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: 'Enter power table name',
                  labelText: 'Power Table Name',
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
              title: Text('Export Power Table'),
              content: TextField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: 'Enter file name',
                  labelText: 'File Name',
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: Text('Export'),
                  onPressed: () => Navigator.of(context).pop(nameController.text),
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
}
