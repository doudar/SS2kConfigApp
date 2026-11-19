import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/file_export.dart';
import 'package:ss2kconfigapp/utils/power_table_sharing.dart';

void main() {
  tearDown(() => FileExport.debugUseSaveDialog = null);

  group('FileExport.baseName', () {
    test('keeps a plain name', () {
      expect(FileExport.baseName('BeforeSeek', '.ptab'), 'BeforeSeek');
    });

    test('drops a typed extension so it is not doubled', () {
      expect(FileExport.baseName('BeforeSeek.ptab', '.ptab'), 'BeforeSeek');
      expect(FileExport.baseName('My bike.SS2K', '.ss2k'), 'My bike');
    });

    test('trims spaces around the name', () {
      expect(FileExport.baseName('  Base table .ptab ', '.ptab'), 'Base table');
    });

    test('leaves other extensions alone', () {
      expect(FileExport.baseName('table.json', '.ptab'), 'table.json');
    });
  });

  test('safeFileName replaces characters Windows does not allow', () {
    expect(FileExport.safeFileName('Bike 1/2.ptab'), 'Bike 1_2.ptab');
    expect(FileExport.safeFileName(r'a<b>c:d"e\f|g?h*i.ptab'),
        'a_b_c_d_e_f_g_h_i.ptab');
    expect(FileExport.safeFileName('BeforeSeek.ptab'), 'BeforeSeek.ptab');
  });

  test('useSaveDialog follows the test override', () {
    FileExport.debugUseSaveDialog = true;
    expect(FileExport.useSaveDialog, isTrue);
    FileExport.debugUseSaveDialog = false;
    expect(FileExport.useSaveDialog, isFalse);
  });

  test('hasData is false for an all-empty table and true with one value', () {
    final empty = List.generate(10, (_) => List<int?>.filled(30, null));
    expect(PowerTableSharing.hasData(empty), isFalse);
    empty[3][7] = 1234;
    expect(PowerTableSharing.hasData(empty), isTrue);
  });
}
