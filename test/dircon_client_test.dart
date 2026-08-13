import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/ftmsControlPoint.dart';
import 'package:ss2kconfigapp/utils/dircon_client.dart';

void main() {
  test('parses fragmented and coalesced DIRCON frames', () {
    final parser = DirConFrameParser();

    expect(parser.add([1, 1, 7]), isEmpty);
    final frames = parser.add([0, 0, 2, 0xaa, 0xbb, 1, 6, 0, 0, 0, 1, 0xcc]);

    expect(frames, hasLength(2));
    expect(frames[0].identifier, 1);
    expect(frames[0].sequence, 7);
    expect(frames[0].body, [0xaa, 0xbb]);
    expect(frames[1].identifier, 6);
    expect(frames[1].sequence, 0);
    expect(frames[1].body, [0xcc]);
  });

  test('encodes the FTMS spin-down command sent over DIRCON', () {
    expect(FTMSControlPoint.spinDownCommand(true), [0x13, 0x01]);
    expect(FTMSControlPoint.spinDownCommand(false), [0x13, 0x02]);
  });
}
