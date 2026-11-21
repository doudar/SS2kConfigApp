import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:ss2kconfigapp/utils/firmware_architecture.dart';
import 'package:ss2kconfigapp/utils/firmware_authenticity.dart';
import 'package:ss2kconfigapp/utils/firmware_release_service.dart';

// This deterministic test key is unrelated to the official trust anchor.
final _curve = ECDomainParameters('prime256v1');
const _release = FirmwareRelease(
  version: '26.9.1',
  downloadUrl: 'https://example.org/release.zip',
  manifestUrl: 'https://example.org/manifest',
  manifestSignatureUrl: 'https://example.org/signature',
);

String _testPem() {
  final spki = ASN1Sequence(
    elements: [
      ASN1Sequence(
        elements: [
          ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.2.1'),
          ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.3.1.7'),
        ],
      ),
      ASN1BitString(stringValues: _curve.G.getEncoded(false)),
    ],
  ).encode();
  return '-----BEGIN PUBLIC KEY-----\n' +
      base64Encode(spki) +
      '\n-----END PUBLIC KEY-----';
}

Uint8List _sign(Uint8List bytes) {
  final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
    ..init(
      true,
      PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(BigInt.one, _curve)),
    );
  final sig = signer.generateSignature(bytes) as ECSignature;
  return ASN1Sequence(
    elements: [ASN1Integer(sig.r), ASN1Integer(sig.s)],
  ).encode();
}

Map<String, Object> _digest(Uint8List value) => {
  'size': value.length,
  'sha256': crypto.sha256.convert(value).toString(),
};

class _ReleaseFixture {
  final verifier = FirmwareAuthenticity.fromPem(_testPem());
  final images = {
    for (final arch in FirmwareArchitecture.values)
      arch: Uint8List(160)
        ..[0] = 0xe9
        ..[12] = arch.espChipId,
  };
  final fetched = <String>[];
  late Uint8List zip, manifest, signature;
  late Map<String, dynamic> fields;

  _ReleaseFixture({
    bool includeImageSignatures = true,
    bool wrongImageSignatures = false,
  }) {
    final archive = Archive();
    for (final entry in images.entries) {
      final filename = entry.key.firmwareFilename;
      archive.add(ArchiveFile.bytes(filename, entry.value));
      if (includeImageSignatures) {
        archive.add(
          ArchiveFile.bytes(
            '$filename.sig',
            _sign(wrongImageSignatures ? Uint8List(7) : entry.value),
          ),
        );
      }
    }
    zip = ZipEncoder().encodeBytes(archive);
    fields = {
      'schema': 1,
      'tag': _release.version,
      'archive': {
        'name': expectedReleaseAssetName(_release.version),
        ..._digest(zip),
      },
      'images': {
        for (final entry in images.entries)
          entry.key.firmwareFilename: _digest(entry.value),
      },
    };
    signManifest();
  }

  void signManifest() {
    manifest = Uint8List.fromList(utf8.encode(jsonEncode(fields)));
    signature = _sign(manifest);
  }

  Future<FirmwareImage> download([
    FirmwareArchitecture arch = FirmwareArchitecture.esp32,
  ]) async {
    final client = MockClient((req) async {
      final path = req.url.path;
      fetched.add(path);
      return http.Response.bytes(switch (path) {
        '/manifest' => manifest,
        '/signature' => signature,
        '/release.zip' => zip,
        _ => throw StateError('Unexpected request: $path'),
      }, 200);
    });
    try {
      return await verifier.download(_release, arch, client);
    } finally {
      client.close();
    }
  }
}

void main() {
  test(
    'both architectures verify all three signatures over their exact bytes',
    () async {
      final f = _ReleaseFixture();
      for (final arch in FirmwareArchitecture.values) {
        final image = await f.download(arch);
        expect(image.official, isTrue);
        expect(image.bytes, f.images[arch]);
        expect(image.filename, arch.firmwareFilename);
        expect(f.verifier.local('release.zip', f.zip, arch).official, isTrue);
      }
      expect(f.fetched, [
        '/manifest',
        '/signature',
        '/release.zip',
        '/manifest',
        '/signature',
        '/release.zip',
      ]);
    },
  );

  test(
    'changing signed JSON whitespace stops before the ZIP request',
    () async {
      final f = _ReleaseFixture();
      f.manifest = Uint8List.fromList([...f.manifest, 32]);
      await expectLater(f.download(), throwsFormatException);
      expect(f.fetched, ['/manifest', '/signature']);
    },
  );

  test(
    'signed wrong version, schema, name or missing target stops before archive',
    () async {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (m) => m['schema'] = 2,
        (m) => m['tag'] = '26.1.1',
        (m) => m['archive']['name'] = 'other.zip',
        (m) => m['images'].remove('S3firmware.bin'),
      ]) {
        final f = _ReleaseFixture();
        mutate(f.fields);
        f.signManifest();
        await expectLater(f.download(), throwsFormatException);
        expect(f.fetched, ['/manifest', '/signature']);
      }
    },
  );

  test('signed archive and image sizes and digests are all enforced', () async {
    for (final target in ['archive', 'firmware.bin']) {
      for (final field in ['size', 'sha256']) {
        final f = _ReleaseFixture();
        final meta = target == 'archive'
            ? f.fields['archive']
            : f.fields['images'][target];
        meta[field] = field == 'size' ? (meta[field] as int) + 1 : '0' * 64;
        f.signManifest();
        await expectLater(f.download(), throwsFormatException);
      }
    }
  });

  test(
    'remote images require their own signature and local unsigned files remain untrusted',
    () async {
      for (final include in [false, true]) {
        final f = _ReleaseFixture(
          includeImageSignatures: include,
          wrongImageSignatures: true,
        );
        await expectLater(f.download(), throwsFormatException);
        expect(
          f.verifier
              .local('release.zip', f.zip, FirmwareArchitecture.esp32)
              .official,
          isFalse,
        );
      }
    },
  );

  test(
    'local raw signature is bound to an owned immutable image and expected chip',
    () {
      final f = _ReleaseFixture();
      final arch = FirmwareArchitecture.esp32;
      final raw = f.images[arch]!;
      final sig = _sign(raw);
      final accepted = f.verifier.local(
        'custom.bin',
        raw,
        arch,
        signature: sig,
      );
      expect(accepted.official, isTrue);
      raw[17] = 5;
      expect(accepted.bytes[17], 0);
      expect(() => accepted.bytes[17] = 0, throwsUnsupportedError);
      expect(
        f.verifier.local('custom.bin', raw, arch, signature: sig).official,
        isFalse,
      );
      expect(f.verifier.local('custom.bin', raw, arch).official, isFalse);
      expect(
        () => f.verifier.local('custom.bin', raw, FirmwareArchitecture.esp32S3),
        throwsFormatException,
      );
    },
  );

  test('corrupt local ZIP cannot bypass the declared extraction bounds', () {
    final f = _ReleaseFixture();
    final bad = Uint8List.fromList(f.zip);
    final header = ByteData.sublistView(bad);
    for (var i = 0; i <= bad.length - 46; i++) {
      if (header.getUint32(i, Endian.little) != 0x02014b50) continue;
      // The genuine image is 160 bytes. Test that actual output is bounded.
      header.setUint32(i + 24, 16, Endian.little);
      break;
    }
    expect(
      () => f.verifier.local('release.zip', bad, FirmwareArchitecture.esp32),
      throwsFormatException,
    );
  });
}
