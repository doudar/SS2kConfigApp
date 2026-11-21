/// Secure custom-characteristic v1. Each SecureClient belongs to one connection.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'ss2k_protocol.dart' as p;

Uint8List _bytes(List<int> data, [int? length]) {
  if ((length != null && data.length != length) ||
      data.any((b) => b < 0 || b > 255)) {
    throw const FormatException('Invalid byte sequence');
  }
  return Uint8List.fromList(data);
}

Uint8List _packet(List<int> data, int opcode, int length) {
  if (data.length != length || data.first != opcode)
    throw const FormatException('Unexpected secure packet');
  return _bytes(data);
}

Uint8List secureInfoRequest() => Uint8List.fromList([p.secure_info]);
Uint8List secureDeviceId(List<int> packet) =>
    _packet(packet, p.secure_identity, 9).sublist(1);

Iterable<Uint8List> secureFragments(List<int> packet, int maxWire) sync* {
  if (packet.isEmpty ||
      packet.length > p.secure_max_wire ||
      packet.first == p.secure_fragment) {
    throw const FormatException('Invalid secure record');
  }
  if (maxWire < 20)
    throw RangeError('Transport capacity must be at least 20 bytes');
  final bytes = _bytes(packet);
  if (bytes.length <= maxWire) {
    yield bytes;
    return;
  }
  final room = maxWire - p.secure_fragment_header;
  for (int at = 0, index = 0; at < bytes.length; at += room, index++) {
    final end = min(at + room, bytes.length);
    yield Uint8List.fromList([
      p.secure_fragment,
      (at == 0 ? 1 : 0) | (end == bytes.length ? 2 : 0),
      index,
      ...bytes.getRange(at, end)
    ]);
  }
}

class SecureAssembler {
  final _pending = BytesBuilder(copy: false);
  int _next = 0;
  void reset() {
    _pending.clear();
    _next = 0;
  }

  Uint8List? add(List<int> wire) {
    try {
      if (wire.isEmpty || wire.length > p.secure_max_wire)
        throw const FormatException('Invalid packet length');
      final bytes = _bytes(wire);
      if (wire.first != p.secure_fragment) {
        if (_next != 0)
          throw const FormatException('Interrupted secure record');
        return bytes;
      }
      if (wire.length <= p.secure_fragment_header)
        throw const FormatException('Missing fragment payload');
      final flags = wire[1], index = wire[2];
      if (flags > 3 ||
          index != _next ||
          (flags.isOdd != (index == 0)) ||
          (index == 0 && wire[3] == p.secure_fragment) ||
          (index == 255 && flags & 2 == 0) ||
          _pending.length + bytes.length - p.secure_fragment_header >
              p.secure_max_wire) {
        throw const FormatException('Invalid fragment sequence');
      }
      _pending.add(Uint8List.sublistView(bytes, p.secure_fragment_header));
      if ((flags & 2) != 0) {
        _next = 0;
        return _pending.takeBytes();
      }
      _next++;
      return null;
    } catch (_) {
      reset();
      rethrow;
    }
  }
}

final _curve = ECDomainParameters('prime256v1');
// SEC 2 secp256r1 field prime. PointyCastle's generic SEC1 decoder accepts
// arbitrary coordinates, so validate canonical encoding and the curve equation.
final _prime = BigInt.parse(
    'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
    radix: 16);
BigInt _integer(List<int> input) =>
    input.fold(BigInt.zero, (n, b) => (n << 8) | BigInt.from(b));
Uint8List _bigEndian32(BigInt n) => Uint8List.fromList(List.generate(
    32, (i) => ((n >> (8 * (31 - i))) & BigInt.from(255)).toInt()));
Uint8List _hash(List<int> bytes) => SHA256Digest().process(_bytes(bytes));
Uint8List _proof(Uint8List root, String label,
    [List<int> transcript = const []]) {
  final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(root));
  return mac
      .process(_bytes([...ascii.encode(label), ...transcript]))
      .sublist(0, 16);
}

void _checkProof(List<int> given, List<int> expected) {
  var diff = 0;
  for (var i = 0; i < expected.length; i++) {
    diff |= expected[i] ^ given[i];
  }
  if (diff != 0) throw const FormatException('Peer authentication failed');
}

Uint8List _derive(Uint8List secret, Uint8List salt, String label, int size) {
  final kdf = HKDFKeyDerivator(SHA256Digest())
    ..init(HkdfParameters(secret, size, salt, _bytes(ascii.encode(label))));
  final out = Uint8List(size);
  kdf.deriveKey(null, 0, out, 0);
  return out;
}

void _wipe(Uint8List? bytes) => bytes?.fillRange(0, bytes.length, 0);

enum _Phase { idle, pairOffer, pairConfirm, challenge, ready, established }

class SecureClient {
  SecureClient({required List<int> deviceId, required List<int> appId})
      : _deviceId = _bytes(deviceId, 8),
        _appId = _bytes(appId, 8);
  final Uint8List _deviceId, _appId;
  final _random = Random.secure();
  _Phase _phase = _Phase.idle;
  Uint8List? _root, _hello, _transcript, _material;
  ECPrivateKey? _private;
  int _send = 0, _received = -1;
  bool get authenticated => _phase == _Phase.established;
  Uint8List get pendingPairKey {
    _expect(_Phase.pairConfirm);
    return _bytes(_root!);
  }

  void _expect(_Phase phase) {
    if (_phase != phase) throw StateError('Unexpected secure-session state');
  }

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  /// Drop this connection's keys and handshake transcript.
  void close() {
    _wipe(_root);
    _wipe(_material);
    _root = null;
    _material = null;
    _private = null;
    _hello = null;
    _transcript = null;
    _phase = _Phase.idle;
    _send = 0;
    _received = -1;
  }

  Uint8List startPair() {
    close();
    final rng = FortunaRandom()..seed(KeyParameter(_randomBytes(32)));
    final generator = ECKeyGenerator()
      ..init(ParametersWithRandom(ECKeyGeneratorParameters(_curve), rng));
    final pair = generator.generateKeyPair();
    _private = pair.privateKey;
    _hello = _bytes(
        [p.secure_pair, ..._appId, ...pair.publicKey.Q!.getEncoded(false)]);
    _phase = _Phase.pairOffer;
    return _bytes(_hello!);
  }

  Uint8List acceptPairOffer(List<int> packet) {
    _expect(_Phase.pairOffer);
    try {
      final offer = _packet(packet, p.secure_offer, 66);
      final x = _integer(offer.sublist(2, 34)), y = _integer(offer.sublist(34));
      if (offer[1] != 4 ||
          x >= _prime ||
          y >= _prime ||
          (y * y -
                      x * x * x -
                      _curve.curve.a!.toBigInteger()! * x -
                      _curve.curve.b!.toBigInteger()!) %
                  _prime !=
              BigInt.zero) {
        throw const FormatException('Invalid P-256 peer public key');
      }
      final peer = _curve.curve.createPoint(x, y);
      final agreement = ECDHBasicAgreement()..init(_private!);
      final secret =
          _bigEndian32(agreement.calculateAgreement(ECPublicKey(peer, _curve)));
      _private = null;
      _root = _derive(secret, _hash([..._hello!, ...offer, ..._deviceId]),
          'SS2K/pair/v1', 32);
      _wipe(secret);
      _phase = _Phase.pairConfirm;
      return _bytes([p.secure_confirm, ..._proof(_root!, 'client')]);
    } catch (_) {
      close();
      rethrow;
    }
  }

  Uint8List confirmPair(List<int> packet) {
    _expect(_Phase.pairConfirm);
    try {
      _checkProof(_packet(packet, p.secure_paired, 17).sublist(1),
          _proof(_root!, 'device'));
      return _bytes(_root!);
    } finally {
      close();
    }
  }

  Uint8List startSession(List<int> root) {
    close();
    _root = _bytes(root, 32);
    _hello = _bytes([p.secure_resume, ..._appId, ..._randomBytes(16)]);
    _phase = _Phase.challenge;
    return _bytes(_hello!);
  }

  Uint8List acceptChallenge(List<int> packet) {
    _expect(_Phase.challenge);
    try {
      final challenge = _packet(packet, p.secure_challenge, 33);
      _transcript =
          _hash([..._deviceId, ..._hello!, ...challenge.getRange(1, 17)]);
      _checkProof(
          challenge.sublist(17), _proof(_root!, 'server', _transcript!));
      _material = _derive(_root!, _transcript!, 'SS2K/session/v1', 64);
      _phase = _Phase.ready;
      return _bytes(
          [p.secure_prove, ..._proof(_root!, 'client', _transcript!)]);
    } catch (_) {
      close();
      rethrow;
    }
  }

  void confirmSession(List<int> packet) {
    _expect(_Phase.ready);
    try {
      _checkProof(_packet(packet, p.secure_ready, 17).sublist(1),
          _proof(_root!, 'ready', _transcript!));
      _wipe(_root);
      _root = null;
      _hello = null;
      _transcript = null;
      _phase = _Phase.established;
    } catch (_) {
      close();
      rethrow;
    }
  }

  Uint8List _crypt(bool encrypt, Uint8List header, Uint8List payload) {
    final m = _material!;
    final key = encrypt ? m.sublist(0, 16) : m.sublist(16, 32);
    final nonce = _bytes([
      ...m.getRange(encrypt ? 32 : 40, encrypt ? 40 : 48),
      ...header.getRange(1, 5)
    ]);
    final ccm = CCMBlockCipher(AESEngine())
      ..init(
          encrypt,
          AEADParameters(
              KeyParameter(key), 8 * p.secure_tag_size, nonce, header));
    return ccm.process(payload);
  }

  Uint8List seal(List<int> inner) {
    _expect(_Phase.established);
    if (inner.length < 2 || inner.length > p.secure_max_inner)
      throw const FormatException('Invalid inner record length');
    if (_send > 0xffffffff) {
      close();
      throw StateError('Session counter exhausted');
    }
    final seq = _send++;
    final header = _bytes(
        [p.secure_data, for (var i = 0; i < 4; i++) (seq >>> (8 * i)) & 255]);
    return _bytes([...header, ..._crypt(true, header, _bytes(inner))]);
  }

  Uint8List open(List<int> packet) {
    _expect(_Phase.established);
    if (packet.length < p.secure_overhead + 2 ||
        packet.length > p.secure_max_wire ||
        packet.first != p.secure_data) {
      throw const FormatException('Invalid encrypted record');
    }
    final bytes = _bytes(packet);
    final seq = ByteData.sublistView(bytes).getUint32(1, Endian.little);
    if (seq <= _received) throw const FormatException('Stale secure record');
    try {
      final plain = _crypt(false, bytes.sublist(0, 5), bytes.sublist(5));
      _received = seq;
      return plain;
    } catch (_) {
      close();
      throw const FormatException('Record authentication failed');
    }
  }
}
