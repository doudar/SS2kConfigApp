import 'dart:async';
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

  test(
    'concurrent setup shares one failed attempt, and the next link restores Android notification mode',
    () async {
      final modes = <bool>[];
      final firstProbe = Completer<void>();
      var probes = 0;
      late PairedCustomLink failed;
      failed = PairedCustomLink(
        alias: 'android',
        deviceName: 'trainer',
        maxWire: 20,
        prompt: null,
        onInner: (_) => fail('Failed link accepted a stale reply'),
        legacyIndications: (enabled) async => modes.add(enabled),
        writeWire: (_) async {
          if (++probes == 1) await firstProbe.future;
          throw TimeoutException('No capability response');
        },
      );
      final first = failed.initialize();
      final waiting = failed.initialize();
      expect(identical(first, waiting), isTrue);
      firstProbe.complete();
      await expectLater(first, throwsA(isA<TimeoutException>()));
      expect(probes, 2);
      expect(modes, [true]);
      expect(failed.needsFreshSession, isTrue);
      failed.receive([p.success, p.CommandId.capabilities, 1, 0, 0, 0, 0]);
      expect(failed.legacy, isFalse);
      late PairedCustomLink next;
      next = PairedCustomLink(
        alias: 'android',
        deviceName: 'trainer',
        maxWire: 20,
        restoreNotificationMode: failed.needsFreshSession,
        prompt: null,
        onInner: received.add,
        legacyIndications: (enabled) async => modes.add(enabled),
        writeWire: (_) async {
          expect(modes, [true, false]);
          next.receive([
            p.secure_identity,
            ...List.filled(8, 0),
          ]); // Delayed reply to an earlier handshake.
          next.receive([p.error, p.CommandId.capabilities]);
        },
      );
      await next.initialize();
      expect(next.legacy, isTrue);
      expect(received, isEmpty);
    },
  );

  test(
    'a notification-mode failure after secure discovery cannot unpin the trainer',
    () async {
      late PairedCustomLink trainer;
      var probes = 0;
      trainer = PairedCustomLink(
        alias: 'android',
        deviceName: 'trainer',
        maxWire: 20,
        prompt: null,
        onInner: (_) => fail('Unexpected settings'),
        legacyIndications: (enabled) async {
          if (!enabled) throw StateError('CCCD unavailable');
        },
        writeWire: (_) async {
          if (++probes == 1)
            throw TimeoutException('No reply in notification mode');
          trainer.receive([
            p.success,
            p.CommandId.capabilities,
            1,
            p.cap_secure_settings,
            0,
            0,
            0,
          ]);
        },
      );
      await expectLater(trainer.initialize(), throwsStateError);
      expect(trainer.needsFreshSession, isTrue);
      expect(
        (await const FlutterSecureStorage().readAll()).values,
        contains('secure'),
      );
    },
  );

  test(
    'successful indication-only legacy discovery keeps indications enabled',
    () async {
      final modes = <bool>[];
      var writes = 0;
      late PairedCustomLink old;
      old = PairedCustomLink(
        alias: 'old',
        deviceName: 'old',
        maxWire: 20,
        prompt: null,
        onInner: received.add,
        legacyIndications: (enabled) async => modes.add(enabled),
        writeWire: (_) async {
          if (++writes == 1) throw TimeoutException('Notify unsupported');
          old.receive([p.error, p.CommandId.capabilities]);
        },
      );
      await old.initialize();
      expect(modes, [true]);
      expect(old.legacy, isTrue);
    },
  );

  test(
    'explicit pairing cancellation does not schedule an unattended retry',
    () async {
      late PairedCustomLink cancelled;
      cancelled = PairedCustomLink(
        alias: 'cancel',
        deviceName: 'trainer',
        maxWire: 234,
        prompt: (_, _, cancel) => cancel(),
        onInner: (_) => fail('Unexpected application frame'),
        writeWire: (request) async {
          if (request.first == p.read) {
            cancelled.receive([
              p.success,
              p.CommandId.capabilities,
              1,
              p.cap_secure_settings,
              0,
              0,
              0,
            ]);
          } else if (request.first == p.secure_info) {
            cancelled.receive([p.secure_identity, ...List.filled(8, 7)]);
          } else {
            fail('Sending a pairing request after cancellation');
          }
        },
      );
      await expectLater(cancelled.initialize(), throwsStateError);
      expect(cancelled.needsFreshSession, isFalse);
      expect(cancelled.authenticated, isFalse);
    },
  );

  test(
    'a pinned companion identity requires explicit legacy consent',
    () async {
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
    },
  );
  for (final closeBeforeApproval in [true, false]) {
    test(
      'only a live connection can remember legacy consent (closed=$closeBeforeApproval)',
      () async {
        final stored = {
          'ss2k_pair_alias_${base64Url.encode(utf8.encode("bench"))}': 'pinned',
          'ss2k_bond_pinned': 'stored-bond',
        };
        FlutterSecureStorage.setMockInitialValues(stored);
        final requested = Completer<void Function()>();
        link = PairedCustomLink(
          alias: 'bench',
          deviceName: 'SmartTestS3',
          maxWire: 20,
          onInner: received.add,
          writeWire: (frame) async {
            writes.add(frame);
            link.receive(probe);
          },
          prompt: (_, _, _) => fail('Legacy firmware cannot exchange keys'),
          confirmLegacy: (name, _, allow, _) => requested.complete(allow),
        );
        final setup = link.initialize();
        expect(identical(setup, link.initialize()), isTrue);
        final allow = await requested.future;
        expect(link.legacy, isFalse);
        if (closeBeforeApproval) link.close();
        allow();
        if (closeBeforeApproval) {
          await expectLater(setup, throwsStateError);
        } else {
          await setup;
        }
        expect(link.legacy, !closeBeforeApproval);
        expect(link.authenticated, isFalse);
        expect(await const FlutterSecureStorage().readAll(), {
          ...stored,
          if (!closeBeforeApproval)
            'ss2k_pair_alias_${base64Url.encode(utf8.encode("bench"))}':
                'legacy:pinned',
        });
        expect(writes, [
          [p.read, p.CommandId.capabilities],
        ]);
      },
    );
  }
  test(
    'remembered consent cannot replace a missing capability reply',
    () async {
      final aliasKey =
          'ss2k_pair_alias_${base64Url.encode(utf8.encode("bench"))}';
      FlutterSecureStorage.setMockInitialValues({
        aliasKey: 'legacy:original-identity',
      });
      final silent = PairedCustomLink(
        alias: 'bench',
        deviceName: 'SmartTestS3',
        maxWire: 234,
        prompt: null,
        onInner: (_) => fail('Unexpected settings'),
        writeWire: (_) async => throw TimeoutException('Trainer unreachable'),
      );
      await expectLater(silent.initialize(), throwsA(isA<TimeoutException>()));
      expect(silent.legacy, isFalse);
    },
  );
  test('an unrecognized capability error cannot select legacy mode', () async {
    probe = [p.error, p.CommandId.capabilities, 1];
    await expectLater(link.initialize(), throwsFormatException);
    expect(link.legacy, isFalse);
  });
  test(
    'reconnect detects legacy firmware and the next secure probe restores the pin',
    () async {
      final aliasKey =
          'ss2k_pair_alias_${base64Url.encode(utf8.encode("bench"))}';
      FlutterSecureStorage.setMockInitialValues({
        aliasKey: 'legacy:original-identity',
      });
      await link.initialize();
      expect(link.legacy, isTrue);
      expect(writes, [
        [p.read, p.CommandId.capabilities],
      ]);
      link.close();

      late PairedCustomLink upgraded;
      upgraded = PairedCustomLink(
        alias: 'bench',
        deviceName: 'SmartTestS3',
        maxWire: 234,
        onInner: (_) => fail('Unexpected settings'),
        prompt: (_, _, _) => fail('Cannot pair a different identity'),
        writeWire: (frame) async {
          if (frame.first == p.read) {
            upgraded.receive([
              p.success,
              p.CommandId.capabilities,
              1,
              p.cap_secure_settings,
              0,
              0,
              0,
            ]);
          } else {
            expect(frame.first, p.secure_info);
            upgraded.receive([p.secure_identity, ...List.filled(8, 3)]);
          }
        },
      );
      await expectLater(
        upgraded.initialize(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('identity changed'),
          ),
        ),
      );
      expect(upgraded.legacy, isFalse);
      expect(
        await const FlutterSecureStorage().read(key: aliasKey),
        'original-identity',
      );
    },
  );
  test(
    'forget clears both transport aliases owned by the verified trainer',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'ss2k_pair_alias_ble': 'trainer1',
        'ss2k_pair_alias_dircon': 'legacy:trainer1',
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
