import 'dart:convert';
import 'dart:io' as io show ZLibDecoder;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:http/http.dart' as http;
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

import 'firmware_architecture.dart';
import 'firmware_release_service.dart';

class FirmwareImage {
  FirmwareImage._(Uint8List bytes, this.filename, this.official)
    : bytes = bytes.asUnmodifiableView();
  final Uint8List bytes;
  final String filename;
  final bool official;
}

class _Digest {
  _Digest(this.size, this.hash);
  final int size;
  final String hash;
  factory _Digest.parse(Object? value, int limit) {
    if (value is! Map || value['size'] is! int || value['sha256'] is! String) {
      throw const FormatException('Invalid signed firmware metadata.');
    }
    final size = value['size'] as int;
    final hash = value['sha256'] as String;
    if (size <= 0 ||
        size > limit ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException(
        'Invalid signed firmware size or SHA-256 digest.',
      );
    }
    return _Digest(size, hash);
  }
  void check(Uint8List data, String name) {
    if (data.length != size || crypto.sha256.convert(data).toString() != hash) {
      throw FormatException(
        'The size or SHA-256 of $name differs from the signed manifest.',
      );
    }
  }
}

class FirmwareAuthenticity {
  FirmwareAuthenticity._(this._key);
  final ECPublicKey _key;
  static const _maxImage = 32 * 1024 * 1024;
  static const maxArchive = 128 * 1024 * 1024;

  factory FirmwareAuthenticity.fromPem(String pem) {
    final lines = pem.trim().split(RegExp(r'\s*\r?\n\s*'));
    if (lines.first != '-----BEGIN PUBLIC KEY-----' ||
        lines.last != '-----END PUBLIC KEY-----') {
      throw const FormatException('Invalid firmware verification key.');
    }
    final parser = ASN1Parser(
      base64.decode(lines.sublist(1, lines.length - 1).join()),
    );
    final spki = parser.nextObject() as ASN1Sequence;
    final algorithm = (spki.elements![0] as ASN1Sequence).elements!;
    final point = spki.elements![1] as ASN1BitString;
    if (parser.hasNext() ||
        spki.elements!.length != 2 ||
        algorithm.length != 2 ||
        (algorithm[0] as ASN1ObjectIdentifier).objectIdentifierAsString !=
            '1.2.840.10045.2.1' ||
        (algorithm[1] as ASN1ObjectIdentifier).objectIdentifierAsString !=
            '1.2.840.10045.3.1.7' ||
        point.unusedbits != 0 ||
        point.stringValues?.length != 65 ||
        point.stringValues!.first != 4) {
      throw const FormatException(
        'Expected a P-256 firmware verification key.',
      );
    }
    final curve = ECDomainParameters('prime256v1');
    return FirmwareAuthenticity._(
      ECPublicKey(
        curve.curve.decodePoint(Uint8List.fromList(point.stringValues!)),
        curve,
      ),
    );
  }

  bool verifies(Uint8List data, Uint8List? derSignature) {
    if (derSignature == null ||
        derSignature.length < 8 ||
        derSignature.length > 72)
      return false;
    try {
      final parser = ASN1Parser(derSignature);
      final components = (parser.nextObject() as ASN1Sequence).elements!;
      if (parser.hasNext() || components.length != 2) return false;
      final r = (components[0] as ASN1Integer).integer!;
      final s = (components[1] as ASN1Integer).integer!;
      final canonical = ASN1Sequence(
        elements: [ASN1Integer(r), ASN1Integer(s)],
      ).encode();
      if (r <= BigInt.zero ||
          s <= BigInt.zero ||
          !listEquals(canonical, derSignature))
        return false;
      final verifier = ECDSASigner(SHA256Digest())
        ..init(false, PublicKeyParameter<ECPublicKey>(_key));
      return verifier.verifySignature(data, ECSignature(r, s));
    } on Object {
      return false;
    }
  }

  Future<Uint8List> _fetch(String url, http.Client client, int limit) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https')
      throw const FormatException('Firmware download requires HTTPS.');
    final response = await client
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 || (response.contentLength ?? 0) > limit) {
      await response.stream.listen((_) {}).cancel();
      throw FormatException(
        'Could not download ${uri.pathSegments.last} (HTTP ${response.statusCode}).',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      if (bytes.length + chunk.length > limit)
        throw const FormatException(
          'Firmware download exceeds its declared size.',
        );
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<FirmwareImage> download(
    FirmwareRelease release,
    FirmwareArchitecture arch,
    http.Client client,
  ) async {
    final manifestUrl = release.manifestUrl,
        signatureUrl = release.manifestSignatureUrl;
    if (manifestUrl == null || signatureUrl == null)
      throw const FormatException('Release has no signed firmware manifest.');
    final raw = await _fetch(manifestUrl, client, 64 * 1024);
    final signature = await _fetch(signatureUrl, client, 72);
    if (!verifies(raw, signature))
      throw const FormatException(
        'The firmware manifest signature could not be verified.',
      );
    final manifest = jsonDecode(utf8.decode(raw));
    if (manifest is! Map ||
        manifest['schema'] is! int ||
        manifest['schema'] != 1 ||
        manifest['tag'] != release.version ||
        manifest['archive'] is! Map ||
        manifest['archive']['name'] !=
            expectedReleaseAssetName(release.version) ||
        manifest['images'] is! Map)
      throw const FormatException(
        'Signed firmware manifest does not match the selected release.',
      );
    final archive = _Digest.parse(manifest['archive'], maxArchive);
    final images = {
      for (final target in FirmwareArchitecture.values)
        target: _Digest.parse(
          manifest['images'][target.firmwareFilename],
          _maxImage,
        ),
    };
    final bytes = await _fetch(release.downloadUrl, client, archive.size);
    archive.check(bytes, expectedReleaseAssetName(release.version));
    final image = _unzip(bytes, arch, images[arch]);
    if (!image.official)
      throw const FormatException(
        'The selected firmware image has no valid official signature.',
      );
    return image;
  }

  FirmwareImage local(
    String filename,
    Uint8List bytes,
    FirmwareArchitecture arch, {
    Uint8List? signature,
  }) {
    if (filename.toLowerCase().endsWith('.zip'))
      return _unzip(bytes, arch, null);
    if (!filename.toLowerCase().endsWith('.bin') || bytes.length > _maxImage)
      throw const FormatException(
        'Select an ESP firmware .bin or release .zip.',
      );
    final owned = Uint8List.fromList(bytes);
    validateFirmwareImage(owned, arch);
    return FirmwareImage._(owned, filename, verifies(owned, signature));
  }

  FirmwareImage _unzip(
    Uint8List bytes,
    FirmwareArchitecture arch,
    _Digest? expected,
  ) {
    if (bytes.length > maxArchive)
      throw const FormatException('Firmware archive is too large.');
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    final headers = directory.fileHeaders;
    final selected = selectFirmwareArchiveEntry(
      headers.map((item) => item.filename),
      arch,
    );
    final header = headers.singleWhere((item) => item.filename == selected);
    if (expected != null && header.uncompressedSize != expected.size) {
      throw const FormatException('Invalid firmware size in ZIP archive.');
    }
    final image = _extract(header, _maxImage);
    validateFirmwareImage(image, arch);
    expected?.check(image, arch.firmwareFilename);
    final signatures = headers.where((h) => h.filename == '$selected.sig');
    final signature =
        signatures.length == 1 &&
            signatures.single.uncompressedSize > 0 &&
            signatures.single.uncompressedSize <= 72
        ? _extract(signatures.single, 72)
        : null;
    return FirmwareImage._(
      image,
      arch.firmwareFilename,
      verifies(image, signature),
    );
  }

  Uint8List _extract(ZipFileHeader header, int limit) {
    final type = (header.externalFileAttributes >> 16) & 0xf000;
    final file = header.file;
    if (file == null ||
        header.uncompressedSize <= 0 ||
        header.uncompressedSize > limit ||
        header.generalPurposeBitFlag & 1 != 0 ||
        (type != 0 && type != 0x8000) ||
        header.compressionMethod != 0 && header.compressionMethod != 8) {
      throw const FormatException('Invalid firmware ZIP entry.');
    }
    final raw = file.getRawContent();
    if (raw.length != header.compressedSize)
      throw const FormatException('Truncated ZIP entry.');
    final sink = _ZipOutput(header.uncompressedSize);
    if (header.compressionMethod == 0) {
      sink.add(raw);
    } else {
      final decoder = io.ZLibDecoder(raw: true).startChunkedConversion(sink);
      // Keep native decompression bounded even if the central directory lies.
      for (int offset = 0; offset < raw.length; offset += 1024) {
        decoder.add(
          Uint8List.sublistView(
            raw,
            offset,
            (offset + 1024).clamp(0, raw.length),
          ),
        );
      }
      decoder.close();
    }
    if (sink.used != sink.bytes.length ||
        getCrc32(sink.bytes) != header.crc32) {
      throw const FormatException('Damaged firmware ZIP entry.');
    }
    return sink.bytes;
  }
}

class _ZipOutput implements Sink<List<int>> {
  _ZipOutput(int size) : bytes = Uint8List(size);
  final Uint8List bytes;
  int used = 0;
  @override
  void add(List<int> chunk) {
    if (chunk.length > bytes.length - used)
      throw const FormatException('ZIP entry exceeded its declared size.');
    bytes.setRange(used, used + chunk.length, chunk);
    used += chunk.length;
  }

  @override
  void close() {}
}
