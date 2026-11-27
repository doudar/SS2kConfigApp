import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as digest;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:ss2k_protocol/secure.dart';
import 'package:ss2k_protocol/ss2k_protocol.dart' as p;
import 'package:ss2kconfigapp/utils/paired_custom_link.dart';

/// Independent trainer-side session/flash receiver for the actual app uploader.
/// WNR writes are delivered in order; their encrypted ACKs arrive on the next
/// event-loop turn, so the test sees the physical flight limit directly.
class _Trainer {
  _Trainer({
    this.dirCon = false,
    this.bits = 0,
    this.wire = 234,
    this.hasWnr = false,
    this.reject = false,
    this.corrupt = false,
    this.dropBegin = false,
    this.brokenWnr = false,
    this.duplicateAcks = false,
  });
  final bool dirCon, hasWnr, reject, corrupt, dropBegin, brokenWnr;
  final bool duplicateAcks;
  int probes = 0;
  final int bits;
  int wire;
  final id = Uint8List.fromList(List.filled(8, 0x24));
  final key = Uint8List.fromList(List.filled(32, 0x41));
  final nonce = List<int>.filled(16, 0x65);
  late final PairedCustomLink app;
  late List<int> transcript;
  final material = Uint8List(64);
  final assembler = SecureAssembler();
  final flash = BytesBuilder();
  late List<int> expectedDigest;
  int expectedSize = 0,
      rx = 0,
      tx = 0,
      maxFlight = 0,
      records = 0,
      writes = 0,
      withoutResponse = 0,
      modeledUs = 0;
  bool started = false, finished = false, aborted = false;
  final sizes = <int>[], flight = <int>[], acks = <Uint8List>[];
  Timer? delivery;

  Future<void> connect() async {
    FlutterSecureStorage.setMockInitialValues({
      'ss2k_bond_${base64UrlEncode(id)}': base64Encode([
        ...List.filled(8, 5),
        ...key,
      ]),
    });
    app = PairedCustomLink(
      alias: 'test',
      deviceName: 'bench',
      maxWire: wire,
      currentMaxWire: () => wire,
      dirCon: dirCon,
      writeWire: (packet) => _write(packet, false),
      writeOtaWithoutResponse: hasWnr ? (packet) => _write(packet, true) : null,
      prompt: (_, _, _) => fail('Unexpected physical enrollment'),
      onInner: (_) {},
    );
    await app.initialize();
  }

  List<int> _proof(String label) => digest.Hmac(
    digest.sha256,
    key,
  ).convert([...ascii.encode(label), ...transcript]).bytes.sublist(0, 16);
  Uint8List _crypt(bool encrypt, Uint8List header, Uint8List data) {
    final k = encrypt ? 16 : 0, n = encrypt ? 40 : 32;
    final c = CCMBlockCipher(AESEngine())
      ..init(
        encrypt,
        AEADParameters(
          KeyParameter(material.sublist(k, k + 16)),
          64,
          Uint8List.fromList([
            ...material.sublist(n, n + 8),
            ...header.skip(1),
          ]),
          header,
        ),
      );
    return c.process(data);
  }

  Uint8List _reply(int op, int offset, {bool ok = true}) {
    final plain = Uint8List(7)
      ..[0] = ok ? p.success : p.error
      ..[1] = p.CommandId.firmwareStream
      ..[2] = op;
    ByteData.sublistView(plain).setUint32(3, offset, Endian.little);
    return _seal(plain);
  }

  Uint8List _seal(Uint8List plain) {
    final header = Uint8List(5)..[0] = p.secure_data;
    ByteData.sublistView(header).setUint32(1, tx++, Endian.little);
    return Uint8List.fromList([...header, ..._crypt(true, header, plain)]);
  }

  // Estimate 1 Mbit/s BLE, 251-byte LL payload, 15 ms connection events:
  // include L2CAP/ATT headers, packet overhead, interframe gaps and link ACKs.
  // The TCP model uses a 10 ms RTT at 100 Mbit/s. Neither includes flash time.
  int _air(int n) {
    final bytes = n + 7;
    return bytes * 8 + ((bytes + 250) ~/ 251) * (14 * 8 + 2 * 150 + 80);
  }

  int _intervals(int us) => max(1, (us + 14999) ~/ 15000) * 15000;
  void _deliver() {
    delivery = null;
    modeledUs += _intervals(
      flight.fold(0, (a, n) => a + _air(n)) +
          acks.fold(0, (a, p) => a + _air(p.length)),
    );
    flight.clear();
    final replies = List<Uint8List>.of(acks);
    acks.clear();
    for (final packet in replies) {
      try {
        app.receive(packet);
        if (duplicateAcks) app.receive(Uint8List.fromList(packet));
      } on FormatException {
        app.invalidate();
      }
    }
  }

  Future<void> _write(List<int> value, bool wnr) async {
    // The extended native TCP packet is never sent through the BLE assembler.
    final frame = dirCon && value.length > p.secure_max_wire
        ? Uint8List.fromList(value)
        : assembler.add(value);
    if (started) {
      writes++;
      if (wnr) {
        withoutResponse++;
        expect(value.length, lessThanOrEqualTo(wire));
        flight.add(value.length);
        maxFlight = max(maxFlight, flight.length);
        delivery ??= Timer(Duration.zero, _deliver);
      } else {
        modeledUs += dirCon
            ? 10000 + (value.length * 8 / 100).ceil()
            : _intervals(_air(value.length) + _air(1) + _air(20));
      }
    }
    if (frame == null) return;
    switch (frame[0]) {
      case p.read:
        app.receive([
          p.success,
          p.CommandId.capabilities,
          1,
          p.cap_secure_settings | bits,
          0,
          0,
          0,
        ]);
        return;
      case p.secure_info:
        app.receive([p.secure_identity, ...id]);
        return;
      case p.secure_resume:
        transcript = digest.sha256.convert([...id, ...frame, ...nonce]).bytes;
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
        app.receive([p.secure_challenge, ...nonce, ..._proof('server')]);
        return;
      case p.secure_prove:
        expect(frame.skip(1), _proof('client'));
        app.receive([p.secure_ready, ..._proof('ready')]);
        return;
    }
    expect(frame.first, p.secure_data);
    final header = frame.sublist(0, 5);
    expect(ByteData.sublistView(header).getUint32(1, Endian.little), rx++);
    final body = _crypt(false, header, frame.sublist(5));
    if (body.first == p.read) {
      expect(body, [p.read, p.CommandId.firmwareVer]);
      expect(wnr, isTrue);
      expect(started, isFalse);
      probes++;
      if (brokenWnr) throw UnsupportedError('Platform rejected WNR');
      app.receive(
        _seal(Uint8List.fromList([p.success, p.CommandId.firmwareVer, 49])),
      );
      return;
    }
    expect(body.sublist(0, 2), [p.write, p.CommandId.firmwareStream]);
    final op = body[2];
    var offset = 0;
    switch (op) {
      case p.ota_begin:
        expect(wnr, isFalse);
        expectedSize = ByteData.sublistView(body).getUint32(3, Endian.little);
        expectedDigest = body.sublist(7);
        started = true;
      case p.ota_chunk:
        expect(started, isTrue);
        expect(
          ByteData.sublistView(body).getUint32(3, Endian.little),
          flash.length,
        );
        if (dirCon && body.length > p.secure_max_inner) {
          expect(bits & p.cap_dircon_ota_2k, isNot(0));
          expect(value.length, frame.length);
        } else {
          expect(body.length, lessThanOrEqualTo(p.secure_max_inner));
        }
        records++;
        sizes.add(body.length - 7);
        flash.add(body.sublist(7));
        offset = flash.length;
        if (reject && records == 1) offset++;
      case p.ota_finish:
        expect(wnr, isFalse);
        expect(flash.length, expectedSize);
        expect(digest.sha256.convert(flash.toBytes()).bytes, expectedDigest);
        finished = true;
        offset = flash.length;
      case p.ota_abort:
        aborted = true;
      default:
        fail('Unexpected OTA operation $op');
    }
    final reply = _reply(op, offset);
    if (dropBegin && op == p.ota_begin) return;
    if (corrupt && op == p.ota_chunk && records == 1)
      reply[reply.length - 1] ^= 1;
    if (wnr) {
      acks.add(reply);
    } else {
      app.receive(reply);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final image = Uint8List.fromList(List.generate(8193, (i) => (37 * i) % 251));
  Future<void> send(_Trainer t) async {
    await t.connect();
    var progress = 0.0;
    await t.app.streamFirmware(image, (next) {
      expect(next, greaterThan(progress));
      progress = next;
    });
    expect(progress, 1);
    expect(t.finished, isTrue);
    expect(t.flash.toBytes(), image);
    expect(t.maxFlight, lessThanOrEqualTo(p.ble_ota_window));
  }

  test('only negotiated DirCon chunks use large native TCP frames', () async {
    final old = _Trainer(dirCon: true);
    final fast = _Trainer(
      dirCon: true,
      bits: p.cap_dircon_ota_2k | p.cap_ble_ota_window4,
      hasWnr: true,
    );
    await send(old);
    await send(fast);
    expect(old.sizes.first, 214);
    expect(fast.sizes.first, 2048);
    expect(old.records, 39);
    expect(fast.records, 5);
    expect(fast.withoutResponse, 0);
    print(
      'DirCon baseline=${old.records} chunks/${old.modeledUs} us; fast=${fast.records}/${fast.modeledUs} us',
    );
  });

  test(
    'a paired BLE upload survives duplicated encrypted acknowledgements',
    () async {
      final trainer = _Trainer(
        bits: p.cap_ble_ota_window4,
        hasWnr: true,
        duplicateAcks: true,
      );
      await send(trainer);
      expect(trainer.withoutResponse, greaterThan(0));
      expect(trainer.aborted, isFalse);
    },
  );

  for (final mtu in [23, 185, 247, 515]) {
    test(
      'OTA ACKs, four-write maximum and negotiated speed at MTU $mtu',
      () async {
        final old = _Trainer(wire: min(mtu - 3, 512));
        final fast = _Trainer(
          wire: min(mtu - 3, 512),
          bits: p.cap_ble_ota_window4,
          hasWnr: true,
        );
        await send(old);
        await send(fast);
        expect(fast.maxFlight, 4);
        expect(fast.withoutResponse, greaterThan(0));
        expect(fast.modeledUs, lessThan(old.modeledUs));
        print(
          'MTU $mtu: baseline=${old.writes} writes/${old.modeledUs} us; fast=${fast.writes}/${fast.modeledUs} us',
        );
      },
    );
  }

  test(
    'a stale GATT cache or old firmware selects acknowledged writes',
    () async {
      for (final t in [
        _Trainer(wire: 244, bits: p.cap_ble_ota_window4),
        _Trainer(wire: 244, hasWnr: true),
        _Trainer(wire: 244, bits: p.cap_dircon_ota_2k, hasWnr: true),
      ]) {
        await send(t);
        expect(t.withoutResponse, 0);
      }
    },
  );

  test(
    'backend write-mode rejection falls back before sending firmware bytes',
    () async {
      final t = _Trainer(
        wire: 244,
        bits: p.cap_ble_ota_window4,
        hasWnr: true,
        brokenWnr: true,
      );
      await send(t);
      expect(t.probes, 1);
      expect(t.withoutResponse, 0);
    },
  );

  test('BLE refreshes the negotiated MTU after pairing', () async {
    final t = _Trainer(wire: 20, bits: p.cap_ble_ota_window4, hasWnr: true);
    await t.connect();
    t.wire = 244;
    await t.app.streamFirmware(image, (_) {});
    expect(t.sizes.first, 224);
  });

  test('lost BEGIN ACK sends ABORT before invalidating the session', () async {
    final t = _Trainer(
      dirCon: true,
      bits: p.cap_dircon_ota_2k,
      dropBegin: true,
    );
    await t.connect();
    await expectLater(
      t.app.streamFirmware(image, (_) => fail('Unexpected progress')),
      throwsA(isA<TimeoutException>()),
    );
    expect(t.aborted, isTrue);
    expect(t.records, 0);
    expect(t.app.needsFreshSession, isTrue);
  });

  test(
    'tampered encrypted chunk ACK cannot advance or finish the upload',
    () async {
      final t = _Trainer(
        wire: 244,
        bits: p.cap_ble_ota_window4,
        hasWnr: true,
        corrupt: true,
      );
      await t.connect();
      await expectLater(
        t.app.streamFirmware(
          image,
          (_) => fail('Invalid tag advanced progress'),
        ),
        throwsStateError,
      );
      expect(t.finished, isFalse);
      expect(t.app.needsFreshSession, isTrue);
    },
  );

  test(
    'bad offset in an authenticated write window aborts without finish',
    () async {
      final t = _Trainer(
        wire: 244,
        bits: p.cap_ble_ota_window4,
        hasWnr: true,
        reject: true,
      );
      await t.connect();
      await expectLater(
        t.app.streamFirmware(
          image,
          (_) => fail('Wrong offset advanced progress'),
        ),
        throwsStateError,
      );
      expect(t.finished, isFalse);
      expect(t.aborted, isTrue);
      expect(t.app.needsFreshSession, isTrue);
    },
  );
}
