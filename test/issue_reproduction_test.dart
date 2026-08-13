
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/device_data.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  test('Reproduction: getPrecision check', () {
    final device = BluetoothDevice.fromId("00:00:00:00:00:00");
    final deviceData = DeviceDataManager.forDevice(device);
    
    final floatChar = {
      "type": "float",
      "reference": "0x00",
      "value": "4.5"
    };
    
    print("Precision for float: ${deviceData.getPrecision(floatChar)}");
    expect(deviceData.getPrecision(floatChar), 2, reason: "Float precision should be 2");
    
    final intChar = {
      "type": "int",
      "reference": "0x01",
      "value": "5"
    };

    print("Precision for int: ${deviceData.getPrecision(intChar)}");
    expect(deviceData.getPrecision(intChar), 0, reason: "Int precision should be 0");
  });
}
