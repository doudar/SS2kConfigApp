import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ss2k_protocol/secure.dart';
import 'package:ss2k_protocol/ss2k_protocol.dart' as protocol;

typedef PairingPrompt =
    void Function(String device, Future<void> approval, void Function() cancel);

class PairingRejected implements Exception {
  const PairingRejected(this.code);
  final int code;
  @override
  String toString() =>
      'SmartSpin2k rejected pairing or authentication (code $code).';
}

/// One instance belongs to exactly one GATT connection or TCP socket.
class PairedCustomLink {
  PairedCustomLink({
    required this.alias,
    required this.deviceName,
    required int maxWire,
    int Function()? currentMaxWire,
    this.dirCon = false,
    this.writeOtaWithoutResponse,
    required this.writeWire,
    required this.onInner,
    required this.prompt,
    this.confirmLegacy,
    this.legacyIndications,
    this.restoreNotificationMode = false,
  }) : _currentMaxWire = currentMaxWire ?? (() => maxWire);
  final String alias;
  final String deviceName;
  final int Function() _currentMaxWire;
  int get maxWire => _currentMaxWire();
  final bool dirCon;
  final Future<void> Function(List<int>)? writeOtaWithoutResponse;
  int _capabilities = 0;
  final Future<void> Function(List<int>) writeWire;
  final void Function(List<int>) onInner;
  final PairingPrompt? prompt;
  final void Function(String, Future<void>, void Function(), void Function())?
  confirmLegacy;
  Completer<void>? _legacyApproval;
  final Future<void> Function(bool enabled)? legacyIndications;
  final bool restoreNotificationMode;
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false, migrateWithBackup: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  final _assembler = SecureAssembler();
  SecureClient? _client;
  Future<void>? _setup;
  bool legacy = false;
  bool authenticated = false;
  bool _closed = false;
  bool _needsFreshSession = false;
  bool get needsFreshSession => _needsFreshSession;
  String? _bondKey;
  String? _identity;
  String? _pendingForgetAppId;
  bool get forgetPending => _pendingForgetAppId != null;
  String get _forgetKey => '${_bondKey!}_forget';
  static const _aliasPrefix = 'ss2k_pair_alias_';
  static const _requiresAuthentication = 'secure';
  // A colon cannot occur in a base64url identity or the unpaired "secure" marker.
  static const _legacyApprovedPrefix = 'legacy:';
  String get _aliasKey =>
      '${_aliasPrefix}${base64Url.encode(utf8.encode(alias))}';
  Completer<List<int>>? _reply;
  bool Function(List<int>)? _matches;
  bool _innerReply = false;

  void close() {
    _closed = true;
    final approval = _legacyApproval;
    if (approval != null && !approval.isCompleted) {
      approval.completeError(StateError('SmartSpin2k connection closed.'));
    }
    authenticated = false;
    legacy = false;
    _client?.close();
    _client = null;
    _assembler.reset();
    final pending = _reply;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('SmartSpin2k connection closed.'));
    }
  }

  void invalidate() {
    // User cancellation and transport teardown close the link deliberately.
    // Background work must not restart a cancelled pairing.
    if (_closed) return;
    _needsFreshSession = true;
    close();
  }

  Future<T> _invalidateOnFailure<T>(Future<T> operation) async {
    try {
      return await operation;
    } catch (_) {
      invalidate();
      rethrow;
    }
  }

  void receive(List<int> wire) {
    if (_closed || wire.isEmpty) return;
    if (legacy) {
      if (wire.first != protocol.secure_notification) onInner(wire);
      return;
    }
    final frame = _assembler.add(wire);
    if (frame == null) return;
    final inner = frame.first == protocol.secure_data;
    if (inner && !authenticated) return;
    final packet = inner ? _client!.open(frame) : frame;
    final waiting = _reply;
    if (waiting != null && !waiting.isCompleted && inner == _innerReply) {
      if (!inner && frame.length == 2 && frame.first == protocol.secure_error) {
        waiting.completeError(PairingRejected(frame[1]));
      } else {
        try {
          if (_matches!(packet)) waiting.complete(packet);
        } catch (error, stack) {
          waiting.completeError(error, stack);
        }
      }
    }
    // Preserve the authenticated opcode so a change cannot be treated as a
    // command acknowledgement anywhere downstream.
    if (inner) onInner(packet);
  }

  Future<List<int>> _exchange(
    List<int> packet,
    bool Function(List<int>) matches, {
    bool inner = false,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    return _awaitReply(
      matches,
      inner: inner,
      timeout: timeout,
      send: () async {
        for (final part in secureFragments(
          inner ? _client!.seal(packet) : packet,
          maxWire,
        )) {
          if (_closed) throw StateError('SmartSpin2k connection closed.');
          await writeWire(part);
        }
      },
    );
  }

  Future<List<int>> _awaitReply(
    bool Function(List<int>) matches, {
    required bool inner,
    required Future<void> Function() send,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_closed) throw StateError('SmartSpin2k connection closed.');
    if (_reply != null)
      throw StateError('A SmartSpin2k request is in progress.');
    final waiter = Completer<List<int>>();
    waiter.future.ignore();
    _reply = waiter;
    _matches = matches;
    _innerReply = inner;
    try {
      await send();
      return await waiter.future.timeout(timeout);
    } finally {
      _reply = null;
      _matches = null;
    }
  }

  Future<List<int>> _handshake(
    List<int> packet,
    int response, {
    Duration timeout = const Duration(seconds: 8),
  }) => _exchange(packet, (frame) => frame.first == response, timeout: timeout);

  Future<void> initialize() => _setup ??= _invalidateOnFailure(_initialize());
  Future<void> _initialize() async {
    // A failed ATT indication probe can leave Android subscribed in that mode.
    // A replacement session starts in notification mode before sending any data.
    if (restoreNotificationMode) await legacyIndications?.call(false);
    Future<List<int>> probe() => _exchange(
      [protocol.read, protocol.CommandId.capabilities],
      (p) =>
          p.length >= 2 &&
          (p[0] == protocol.success || p[0] == protocol.error) &&
          p[1] == protocol.CommandId.capabilities,
    );
    late List<int> capability;
    var forcedIndications = false;
    try {
      capability = await probe();
    } on TimeoutException {
      final toggle = legacyIndications;
      if (toggle == null || _closed) rethrow;
      // Some older firmware declares both properties but answers reads only
      // using ATT indications. Android exposes an explicit choice for its CCCD.
      await toggle(true);
      forcedIndications = true;
      capability = await probe();
    }
    final storedPin = await _storage.read(key: _aliasKey);
    final legacyApproved =
        storedPin?.startsWith(_legacyApprovedPrefix) ?? false;
    final pinned = legacyApproved
        ? storedPin!.substring(_legacyApprovedPrefix.length)
        : storedPin;
    if (_closed) throw StateError('SmartSpin2k connection closed.');
    if (capability.first == protocol.success &&
        (capability.length != 7 || capability[2] != 1)) {
      throw const FormatException('Unknown SmartSpin2k capability format.');
    }
    if (capability.first == protocol.error && capability.length != 2) {
      throw const FormatException('Unknown SmartSpin2k capability error.');
    }
    if (capability.first == protocol.error ||
        capability[3] & protocol.cap_secure_settings == 0) {
      if (pinned != null && !legacyApproved) {
        final confirm = confirmLegacy;
        if (confirm == null) {
          throw StateError(
            'This paired SmartSpin2k requires an encrypted connection.',
          );
        }
        final approval = _legacyApproval = Completer<void>();
        approval.future.ignore();
        try {
          confirm(deviceName, approval.future, () {
            if (!_closed && !approval.isCompleted) approval.complete();
          }, close);
          await approval.future;
          if (_closed) throw StateError('SmartSpin2k connection closed.');
          await _storage.write(
            key: _aliasKey,
            value: '$_legacyApprovedPrefix$pinned',
          );
          if (_closed) throw StateError('SmartSpin2k connection closed.');
        } finally {
          _legacyApproval = null;
        }
      }
      legacy = true;
      return;
    }

    _capabilities = ByteData.sublistView(
      Uint8List.fromList(capability),
    ).getUint32(3, Endian.little);
    // Seeing secure capabilities ends legacy consent even if authentication
    // subsequently fails. Preserve the original identity for verification.
    if (pinned == null || legacyApproved) {
      await _storage.write(
        key: _aliasKey,
        value: pinned ?? _requiresAuthentication,
      );
    }
    if (forcedIndications) await legacyIndications!(false);
    final deviceId = secureDeviceId(
      await _handshake(secureInfoRequest(), protocol.secure_identity),
    );
    final identity = base64Url.encode(deviceId);
    if (pinned != null &&
        pinned != _requiresAuthentication &&
        pinned != identity)
      throw StateError('SmartSpin2k pairing identity changed.');
    _identity = identity;
    _bondKey = 'ss2k_bond_$identity';
    _pendingForgetAppId = await _storage.read(key: _forgetKey);
    if (!forgetPending) await _authenticate(deviceId);
  }

  Future<void> _authenticate(List<int> deviceId) async {
    final committed = await _storage.read(key: _bondKey!);
    final stagingKey = '${_bondKey!}_pending';
    final staged = await _storage.read(key: stagingKey);
    for (final candidate in [staged, committed].whereType<String>().toSet()) {
      final bond = base64Decode(candidate);
      if (bond.length != 40)
        throw StateError('Invalid stored SmartSpin2k pairing.');
      final client = SecureClient(
        deviceId: deviceId,
        appId: bond.sublist(0, 8),
      );
      _client = client;
      try {
        await _resume(client, bond.sublist(8));
        if (candidate != committed)
          await _storage.write(key: _bondKey!, value: candidate);
        if (staged != null) await _storage.delete(key: stagingKey);
        return;
      } on PairingRejected catch (error) {
        client.close();
        if (error.code != 3) rethrow;
      }
    }
    if (_closed) throw StateError('SmartSpin2k connection closed.');
    final rng = Random.secure();
    final appId = forgetPending
        ? base64Decode(_pendingForgetAppId!)
        : Uint8List.fromList(List.generate(8, (_) => rng.nextInt(256)));
    final client = SecureClient(deviceId: deviceId, appId: appId);
    _client = client;
    final approval = Completer<void>();
    approval.future.ignore();
    try {
      prompt?.call(deviceName, approval.future, close);
      final offer = await _handshake(
        client.startPair(),
        protocol.secure_offer,
        timeout: const Duration(seconds: 65),
      );
      final proof = client.acceptPairOffer(offer);
      if (_closed) throw StateError('Pairing cancelled.');
      // Save before confirming so losing the final acknowledgement is recoverable.
      final candidate = base64Encode([...appId, ...client.pendingPairKey]);
      await _storage.write(key: stagingKey, value: candidate);
      final acknowledged = await _handshake(proof, protocol.secure_paired);
      final key = client.confirmPair(acknowledged);
      await _resume(client, key);
      await _storage.write(key: _bondKey!, value: candidate);
      await _storage.delete(key: stagingKey);
      approval.complete();
    } catch (error, stack) {
      approval.completeError(error, stack);
      rethrow;
    }
  }

  Future<void> _resume(SecureClient client, List<int> key) async {
    final challenge = await _handshake(
      client.startSession(key),
      protocol.secure_challenge,
    );
    final ready = await _handshake(
      client.acceptChallenge(challenge),
      protocol.secure_ready,
    );
    client.confirmSession(ready);
    if (_closed) throw StateError('Pairing cancelled.');
    await _storage.write(key: _aliasKey, value: _identity!);
    if (_closed) throw StateError('Pairing cancelled.');
    authenticated = true;
  }

  Future<List<int>> command(List<int> packet) async {
    protocol.validateRequest(packet);
    // After an ambiguous write, a late ACK could match a subsequent request.
    // Re-negotiate traffic keys before the next operation.
    return _invalidateOnFailure(
      _exchange(
        packet,
        (p) =>
            p.length >= 2 &&
            p[1] == packet[1] &&
            (p[0] == protocol.success || p[0] == protocol.error),
        inner: true,
      ),
    );
  }

  /// A firmware chunk is complete only when the device acknowledges its flash
  /// offset inside the authenticated session, including write-without-response.
  Future<void> streamFirmware(
    Uint8List firmware,
    void Function(double) onProgress,
  ) async {
    if (forgetPending || !authenticated) {
      throw StateError('The firmware update requires a paired connection.');
    }
    if (firmware.isEmpty) throw const FormatException('Firmware is empty.');
    final wireLimit = maxWire;
    final largeDirCon =
        dirCon && _capabilities & protocol.cap_dircon_ota_2k != 0;
    final fastBle =
        !dirCon &&
        writeOtaWithoutResponse != null &&
        _capabilities & protocol.cap_ble_ota_window4 != 0 &&
        await _supportsOtaWritesWithoutResponse();
    // At the default ATT MTU a data record cannot fit in one write. Spend the
    // entire four-write credit on one fragmented record and wait for its ACK.
    final fragmentBle = fastBle && wireLimit < 64;
    final int chunkSize;
    if (largeDirCon) {
      chunkSize = protocol.dircon_ota_chunk_bytes;
    } else if (fragmentBle) {
      chunkSize =
          protocol.ble_ota_window *
              (wireLimit - protocol.secure_fragment_header) -
          _otaOverhead;
    } else if (fastBle) {
      chunkSize = wireLimit - _otaOverhead;
    } else {
      chunkSize = pairedFirmwareChunkSize(wireLimit);
    }
    final window = fastBle && !fragmentBle ? protocol.ble_ota_window : 1;
    Future<void> control(int op, List<int> body, int end) async {
      final request = [
        protocol.write,
        protocol.CommandId.firmwareStream,
        op,
        ...body,
      ];
      protocol.validateRequest(request);
      // Keep this session available for the best-effort ABORT if BEGIN's ACK
      // is lost. The trainer may already own the inactive flash partition.
      final reply = await _exchange(
        request,
        (p) =>
            p.length >= 3 &&
            p[1] == protocol.CommandId.firmwareStream &&
            p[2] == op &&
            (p[0] == protocol.success || p[0] == protocol.error),
        inner: true,
      );
      _checkOtaAck(reply, op, end);
    }

    try {
      await control(protocol.ota_begin, [
        ..._le32(firmware.length),
        ...crypto.sha256.convert(firmware).bytes,
      ], 0);
      for (
        var offset = 0;
        offset < firmware.length;
        offset += window * chunkSize
      ) {
        final windowEnd = min(offset + window * chunkSize, firmware.length);
        await _sendFirmwareWindow(
          firmware,
          offset,
          windowEnd,
          chunkSize,
          wireLimit: wireLimit,
          largeDirCon: largeDirCon,
          fastBle: fastBle,
          onAcknowledged: (end) => onProgress(end / firmware.length),
        );
      }
      await control(protocol.ota_finish, [], firmware.length);
    } catch (_) {
      if (authenticated) {
        // Already-sent chunk ACKs may arrive before ABORT. Only ABORT's own
        // authenticated response ends this exchange. Never retry image data.
        try {
          await _exchange(
            [
              protocol.write,
              protocol.CommandId.firmwareStream,
              protocol.ota_abort,
            ],
            (p) =>
                p.length == 7 &&
                p[1] == protocol.CommandId.firmwareStream &&
                p[2] == protocol.ota_abort &&
                (p.first == protocol.success || p.first == protocol.error),
            inner: true,
            timeout: const Duration(seconds: 2),
          );
        } catch (_) {}
        invalidate();
      }
      rethrow;
    }
  }

  Future<bool> _supportsOtaWritesWithoutResponse() async {
    // Some host GATT caches misreport write modes after a firmware upgrade.
    // Probe with a read before BEGIN, so falling back cannot duplicate a flash write.
    final id = protocol.CommandId.firmwareVer;
    try {
      final response = await _awaitReply(
        (packet) =>
            packet.length >= 2 &&
            packet[1] == id &&
            (packet[0] == protocol.success || packet[0] == protocol.error),
        inner: true,
        timeout: const Duration(seconds: 2),
        send: () =>
            writeOtaWithoutResponse!(_client!.seal([protocol.read, id])),
      );
      return response.first == protocol.success;
    } catch (_) {
      if (!authenticated) rethrow;
      return false;
    }
  }

  Future<void> _sendFirmwareWindow(
    Uint8List image,
    int start,
    int end,
    int chunkSize, {
    required int wireLimit,
    required bool largeDirCon,
    required bool fastBle,
    required void Function(int) onAcknowledged,
  }) async {
    var sent = start, acknowledged = start;
    await _awaitReply(
      (packet) {
        if (packet.length < 2 ||
            packet[1] != protocol.CommandId.firmwareStream ||
            packet.first == protocol.secure_notification)
          return false;
        final next = min(acknowledged + chunkSize, end);
        if (next > sent)
          throw StateError('Unexpected firmware acknowledgement.');
        _checkOtaAck(packet, protocol.ota_chunk, next);
        acknowledged = next;
        onAcknowledged(next);
        return next == end;
      },
      inner: true,
      send: () async {
        while (sent < end) {
          if (_closed) throw StateError('SmartSpin2k connection closed.');
          final next = min(sent + chunkSize, end);
          final inner = Uint8List(7 + next - sent);
          inner[0] = protocol.write;
          inner[1] = protocol.CommandId.firmwareStream;
          inner[2] = protocol.ota_chunk;
          ByteData.sublistView(inner).setUint32(3, sent, Endian.little);
          inner.setRange(7, inner.length, image, sent);
          final wire = _client!.seal(inner, dirConOta: largeDirCon);
          sent = next;
          if (largeDirCon) {
            await writeWire(wire);
          } else {
            final write = fastBle ? writeOtaWithoutResponse! : writeWire;
            for (final fragment in secureFragments(wire, wireLimit)) {
              if (_closed) throw StateError('SmartSpin2k connection closed.');
              await write(fragment);
            }
          }
          if (_reply!.isCompleted) break;
        }
      },
    );
  }

  static Future<void> removeAliases(String identity) async {
    for (final entry in (await _storage.readAll()).entries.toList(
      growable: false,
    )) {
      if (entry.key.startsWith(_aliasPrefix) &&
          (entry.value == identity ||
              entry.value == '$_legacyApprovedPrefix$identity')) {
        await _storage.delete(key: entry.key);
      }
    }
  }

  Future<void> forget() async {
    if (_identity == null || _closed)
      throw StateError('Reconnect to finish unpairing the trainer.');
    if (!forgetPending) {
      if (!authenticated) throw StateError('No authenticated pairing.');
      final saved = await _storage.read(key: _bondKey!);
      if (saved == null) throw StateError('The saved pairing is unavailable.');
      _pendingForgetAppId = base64Encode(base64Decode(saved).sublist(0, 8));
      await _storage.write(key: _forgetKey, value: _pendingForgetAppId);
    }
    // Only this explicit user action may repair an interrupted revocation.
    // Replacing the same app ID makes the old key unusable, even after an ACK
    // was lost. The replacement is immediately revoked and acknowledged too.
    if (!authenticated)
      await _invalidateOnFailure(_authenticate(base64Url.decode(_identity!)));
    final reply = await command([
      protocol.write,
      protocol.CommandId.forgetPeer,
    ]);
    if (reply.first != protocol.success)
      throw StateError('SmartSpin2k rejected forget.');
    await removeCredential();
  }

  Future<void> removeCredential() async {
    if (_identity != null) await removeAliases(_identity!);
    if (_bondKey != null) {
      await _storage.delete(key: _bondKey!);
      await _storage.delete(key: '${_bondKey!}_pending');
      await _storage.delete(key: _forgetKey);
    }
    _pendingForgetAppId = null;
    close();
  }
}

const _otaOverhead = protocol.secure_overhead + 7;
List<int> _le32(int value) => [
  for (int shift = 0; shift < 32; shift += 8) (value >> shift) & 255,
];

void _checkOtaAck(List<int> packet, int op, int expected) {
  if (packet.length != 7 ||
      packet[0] != protocol.success ||
      packet[1] != protocol.CommandId.firmwareStream ||
      packet[2] != op ||
      ByteData.sublistView(
            Uint8List.fromList(packet),
          ).getUint32(3, Endian.little) !=
          expected) {
    throw StateError(
      'SmartSpin2k rejected the firmware transfer at offset $expected.',
    );
  }
}

/// Keep ordinary transfers in one ATT/DirCon packet. Small negotiated MTUs
/// use a group of whole fragments per authenticated flash acknowledgement.
int pairedFirmwareChunkSize(int maxWire) {
  const overhead = _otaOverhead;
  if (maxWire >= overhead + 128) return maxWire - overhead;
  final fragmentPayload = maxWire - protocol.secure_fragment_header;
  return ((256 + overhead) ~/ fragmentPayload) * fragmentPayload - overhead;
}
