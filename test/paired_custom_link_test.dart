import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as digest;
import 'package:pointycastle/export.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2k_protocol/ss2k_protocol.dart' as p;
import 'package:ss2kconfigapp/utils/paired_custom_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<List<int>> writes;
  late List<List<int>> received;
  late PairedCustomLink link;
  late List<int> probe;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    writes = [];
    received = [];
    probe = [p.error, p.CommandId.capabilities];
    link = PairedCustomLink(
      alias: 'bench',
      deviceName: 'SmartBench',
      maxWire: 20,
      onInner: received.add,
      prompt: null,
      writeWire: (frame) async {
        writes.add(frame);
        link.receive(probe);
      },
    );
  });
  test(
    'an explicit unsupported capabilities response selects old firmware',
    () async {
      await link.initialize();
      expect(link.legacy, isTrue);
      expect(link.authenticated, isFalse);
      expect(writes, [
        [p.read, p.CommandId.capabilities],
      ]);
      link.receive([p.secure_notification, 8, 99, 0]);
      link.receive([p.success, 8, 77, 0]);
      expect(received, [
        [p.success, 8, 77, 0],
      ]);
    },
  );
  test(
    'an authenticated change and the same-reference reply remain distinct',
    () async {
      final deviceId = Uint8List.fromList(List.filled(8, 3));
      final appId = List.filled(8, 4);
      final key = Uint8List.fromList(List.filled(32, 5));
      FlutterSecureStorage.setMockInitialValues({
        'ss2k_bond_${base64UrlEncode(deviceId)}': base64Encode([
          ...appId,
          ...key,
        ]),
      });
      final nonce = List.filled(16, 6);
      late List<int> transcript;
      final material = Uint8List(64);
      List<int> proof(String label) => digest.Hmac(
        digest.sha256,
        key,
      ).convert([...ascii.encode(label), ...transcript]).bytes.sublist(0, 16);
      Uint8List record(int sequence, List<int> plain) {
        final header = Uint8List.fromList([p.secure_data, sequence, 0, 0, 0]);
        final cipher = CCMBlockCipher(AESEngine())
          ..init(
            true,
            AEADParameters(
              KeyParameter(material.sublist(16, 32)),
              64,
              Uint8List.fromList([
                ...material.sublist(40, 48),
                ...header.skip(1),
              ]),
              header,
            ),
          );
        return Uint8List.fromList([
          ...header,
          ...cipher.process(Uint8List.fromList(plain)),
        ]);
      }

      final change = [p.secure_notification, p.CommandId.shifterPosition, 4, 0];
      final reply = [p.success, p.CommandId.shifterPosition, 5, 0];
      late PairedCustomLink paired;
      paired = PairedCustomLink(
        alias: 'bench',
        deviceName: 'bench',
        maxWire: 234,
        prompt: (_, _, _) => fail('Stored credentials should resume'),
        onInner: received.add,
        writeWire: (frame) async {
          switch (frame.first) {
            case p.read:
              paired.receive([
                p.success,
                p.CommandId.capabilities,
                1,
                p.cap_secure_settings,
                0,
                0,
                0,
              ]);
            case p.secure_info:
              paired.receive([p.secure_identity, ...deviceId]);
            case p.secure_resume:
              transcript = digest.sha256.convert([
                ...deviceId,
                ...frame,
                ...nonce,
              ]).bytes;
              final derive = HKDFKeyDerivator(SHA256Digest())
                ..init(
                  HkdfParameters(
                    key,
                    64,
                    Uint8List.fromList(transcript),
                    Uint8List.fromList(ascii.encode('SS2K/session/v1')),
                  ),
                );
              derive.deriveKey(null, 0, material, 0);
              paired.receive([
                p.secure_challenge,
                ...nonce,
                ...proof('server'),
              ]);
            case p.secure_prove:
              expect(frame.skip(1), proof('client'));
              paired.receive([p.secure_ready, ...proof('ready')]);
            case p.secure_data:
              paired.receive(record(0, change));
              paired.receive(record(1, reply));
            default:
              fail('Unexpected secure request');
          }
        },
      );
      await paired.initialize();
      expect(
        await paired.command([p.read, p.CommandId.shifterPosition]),
        reply,
      );
      expect(received, [change, reply]);
      expect(
        p
            .decodeResponse(received.first, kind: p.ReplyKind.notification)
            .rawValue,
        4,
      );
      paired.close();
    },
  );

  test('a pinned companion identity never falls back to plaintext', () async {
    FlutterSecureStorage.setMockInitialValues({
      'ss2k_pair_alias_${base64Url.encode(utf8.encode("bench"))}': 'pinned',
    });
    await expectLater(link.initialize(), throwsStateError);
    link.receive([p.success, 8, 77, 0]);
    expect(link.legacy, isFalse);
    expect(received, isEmpty);
    expect(writes, [
      [p.read, p.CommandId.capabilities],
    ]);
  });
  test(
    'forget clears both transport aliases owned by the verified trainer',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'ss2k_pair_alias_ble': 'trainer1',
        'ss2k_pair_alias_dircon': 'trainer1',
        'ss2k_pair_alias_other': 'trainer2',
        'another_key': 'trainer1',
      });
      await PairedCustomLink.removeAliases('trainer1');
      expect(await const FlutterSecureStorage().readAll(), {
        'ss2k_pair_alias_other': 'trainer2',
        'another_key': 'trainer1',
      });
    },
  );
  test(
    'an interrupted forget never re-pairs unattended or deletes the old root',
    () async {
      final id = List.filled(8, 7);
      final identity = base64Url.encode(id);
      final stored = {
        'ss2k_bond_$identity': base64Encode(List.filled(40, 8)),
        'ss2k_bond_${identity}_forget': base64Encode(List.filled(8, 8)),
      };
      FlutterSecureStorage.setMockInitialValues(stored);
      late PairedCustomLink trainer;
      trainer = PairedCustomLink(
        alias: 'bench',
        deviceName: 'bench',
        maxWire: 234,
        prompt: (_, _, _) => fail('Unattended re-pairing requested'),
        onInner: (_) {},
        writeWire: (frame) async {
          if (frame.first == p.read) {
            trainer.receive([
              p.success,
              p.CommandId.capabilities,
              1,
              p.cap_secure_settings,
              0,
              0,
              0,
            ]);
          } else if (frame.first == p.secure_info) {
            trainer.receive([p.secure_identity, ...id]);
          } else {
            fail('Unexpected attempt to use or replace the old key');
          }
        },
      );
      await trainer.initialize();
      expect(trainer.forgetPending, isTrue);
      expect(trainer.authenticated, isFalse);
      expect(
        await const FlutterSecureStorage().read(key: 'ss2k_bond_$identity'),
        stored['ss2k_bond_$identity'],
      );
    },
  );
  test('malformed capability successes do not authorize plaintext', () async {
    probe = [p.success, p.CommandId.capabilities];
    await expectLater(link.initialize(), throwsFormatException);
    expect(link.legacy, isFalse);
  });
  test(
    'small MTUs stream many firmware bytes per verified flash acknowledgement',
    () {
      expect(pairedFirmwareChunkSize(20), 252);
      expect(pairedFirmwareChunkSize(234), 214);
      expect(pairedFirmwareChunkSize(512), 492);
    },
  );
}
