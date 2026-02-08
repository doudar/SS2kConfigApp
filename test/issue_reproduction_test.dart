
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/bledata.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  test('Reproduction: getPrecision check', () {
    final device = BluetoothDevice.fromId("00:00:00:00:00:00");
    final bleData = BLEDataManager.forDevice(device);
    
    final floatChar = {
      "type": "float",
      "reference": "0x00",
      "value": "4.5"
    };
    
    print("Precision for float: ${bleData.getPrecision(floatChar)}");
    expect(bleData.getPrecision(floatChar), 2, reason: "Float precision should be 2");
    
    final intChar = {
      "type": "int",
      "reference": "0x01",
      "value": "5"
    };

    print("Precision for int: ${bleData.getPrecision(intChar)}");
    expect(bleData.getPrecision(intChar), 0, reason: "Int precision should be 0");
  });
}
