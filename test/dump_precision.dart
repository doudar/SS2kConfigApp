
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/bledata.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  test('Dump characteristics precision', () {
    final device = BluetoothDevice.fromId("00:00:00:00:00:00");
    final bleData = BLEDataManager.forDevice(device);
    
    // customCharacteristicFramework is List<dynamic> (maps)
    for (var c in customCharacteristicFramework) {
      int prec = bleData.getPrecision(c);
      print("Name: ${c['humanReadableName']}, Type: ${c['type']}, Precision: $prec");
      
      if (c['type'] == 'float' && prec == 0) {
        fail("Float characteristic ${c['humanReadableName']} has precision 0!");
      }
    }
  });
}
