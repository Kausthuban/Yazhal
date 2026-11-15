import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:yazhal/services/public_network_client.dart';

class ProviderQuality {
  const ProviderQuality(
    this.id,
    this.label, {
    this.kind = '',
    this.description = '',
  });
  factory ProviderQuality.parse(Map m) => ProviderQuality(
    m['id'].toString(),
    (m['label'] ?? m['id']).toString(),
    kind: (m['kind'] ?? '').toString(),
    description: (m['description'] ?? '').toString(),
  );
  final String id, label, kind, description;
}

class ExtensionPackage {
  ExtensionPackage({
    required this.id,
    required this.manifest,
    required this.source,
    required this.digest,
    required this.licenses,
  });
  final String id, source, digest;
  final Map<String, dynamic> manifest;
  final Map<String, String> licenses;
  String get name =>
      (manifest['displayName'] ?? manifest['name'] ?? id).toString();
  String get author =>
      (manifest['author'] ?? 'Author not declared; see package notices')
          .toString();
  String get version => manifest['version'].toString();
  List<String> get types =>
      (manifest['type'] is List ? manifest['type'] as List : [manifest['type']])
          .whereType<String>()
          .toList();
  List<String> get hosts =>
      ((manifest['permissions'] as Map?)?['network'] as List? ?? [])
          .whereType<String>()
          .toList();
  List<ProviderQuality> get qualities =>
      (manifest['qualityOptions'] as List? ?? [])
          .whereType<Map>()
          .map(ProviderQuality.parse)
          .toList();
  List<Map> get settings =>
      (manifest['settings'] as List? ?? []).whereType<Map>().toList();
  bool allows(Uri uri) =>
      PublicNetworkClient.publicHttps(uri) &&
      hosts.any(
        (h) =>
            h == '*' ||
            uri.host == h ||
            (h.startsWith('*.') &&
                uri.host.endsWith(h.substring(1)) &&
                uri.host != h.substring(2)),
      );
  static ExtensionPackage decode(String id, List<int> bytes, String checksum) {
    if (!RegExp(r'^[a-z][a-z0-9_-]{1,79}$').hasMatch(id) ||
        bytes.length > 8 * 1024 * 1024)
      throw const FormatException('Invalid extension identity or package size');
    final digest = sha256.convert(bytes).toString();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum) || digest != checksum)
      throw const FormatException('Extension checksum mismatch');
    var declaredTotal = 0, count = 0;
    final names = <String>{};
    for (final header in ZipDirectory().headers(
      InputMemoryStream(bytes),
      verify: true,
      files: false,
    )) {
      final name = header.filename;
      declaredTotal += header.uncompressedSize;
      if (++count > 100 ||
          header.uncompressedSize < 0 ||
          header.uncompressedSize > 4 * 1024 * 1024 ||
          declaredTotal > 12 * 1024 * 1024 ||
          (header.externalFileAttributes >> 16) & 0xf000 == 0xa000 ||
          name.startsWith('/') ||
          name.contains('\\') ||
          name.split('/').contains('..') ||
          !names.add(name))
        throw const FormatException('Unsafe extension archive directory');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.length > 100)
      throw const FormatException('Too many package files');
    var total = 0;
    final seen = <String>{};
    final contents = <String, List<int>>{};
    for (final f in archive) {
      final n = f.name;
      total += f.size;
      if (n.startsWith('/') ||
          n.contains('\\') ||
          n.split('/').contains('..') ||
          !seen.add(n) ||
          f.size > 4 * 1024 * 1024 ||
          total > 12 * 1024 * 1024 ||
          f.isSymbolicLink)
        throw const FormatException('Unsafe extension archive');
      if (f.isFile) contents[n] = f.content;
    }
    final raw = contents['manifest.json'];
    final source = contents['index.js'];
    if (raw == null ||
        raw.length > 65536 ||
        source == null ||
        source.length > 2 * 1024 * 1024)
      throw const FormatException('Expected manifest.json and index.js');
    final decoded = jsonDecode(utf8.decode(raw));
    if (decoded is! Map)
      throw const FormatException('Invalid extension manifest');
    final manifest = Map<String, dynamic>.from(decoded);
    if (manifest['name'] is! String ||
        manifest['version'] is! String ||
        (manifest['displayName']?.toString().length ?? 0) > 160)
      throw const FormatException('Invalid extension metadata');
    final permissions = manifest['permissions'];
    if (permissions is! Map ||
        permissions['network'] is! List ||
        (permissions['network'] as List).length > 100)
      throw const FormatException('Expected declared network permissions');
    for (final h in permissions['network'] as List) {
      if (h is! String ||
          (h != '*' &&
              !RegExp(r'^(\*\.)?[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}$')
                  .hasMatch(h)))
        throw const FormatException('Invalid network permission');
    }
    final licenses = <String, String>{};
    for (final entry in contents.entries) {
      if (RegExp(
        r'(^|/)(LICENSE|COPYING|NOTICE)(\.[A-Za-z]+)?$',
        caseSensitive: false,
      ).hasMatch(entry.key))
        licenses[entry.key] = utf8.decode(entry.value, allowMalformed: true);
    }
    if (licenses.isEmpty)
      throw const FormatException(
        'Package must retain its license or author notice',
      );
    return ExtensionPackage(
      id: id,
      manifest: manifest,
      source: utf8.decode(source),
      digest: digest,
      licenses: licenses,
    );
  }
}
