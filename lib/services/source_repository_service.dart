import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:yazhal/services/audio_relay_service.dart';
import 'package:yazhal/services/flac_extension_service.dart';
import 'package:yazhal/services/public_network_client.dart';

/// Declarative catalog repositories. JavaScript packages are listed, never run.
class SourceRepositoryEntry {
  SourceRepositoryEntry(this.data);
  final Map data;
  String get id => data['id']?.toString() ?? '';
  String get name =>
      (data['display_name'] ?? data['displayName'] ?? data['name'] ?? id)
          .toString();
  String get runtime => data['runtime']?.toString() ?? 'javascript';
  bool get compatible => runtime == 'yazhal-catalog-v1';
  bool get javascript => {'', 'javascript', 'JavaScript'}.contains(runtime);
  String get description => data['description']?.toString() ?? '';
  String get downloadUrl =>
      (data['manifestUrl'] ?? data['download_url'] ?? data['downloadUrl'] ?? '')
          .toString();
  String get checksum =>
      (data['sha256'] ??
              data['checksum_sha256'] ??
              data['checksumSha256'] ??
              '')
          .toString()
          .toLowerCase();
}

class SourceRepositoryService {
  SourceRepositoryService({http.Client? client})
    : client = client ?? PublicNetworkClient.create();
  final http.Client client;
  static List<Map> get repositories => (Hive.box('settings').get(
    'sourceRepositories',
    defaultValue: [
      {
        'url': 'https://raw.githubusercontent.com/zarzet/SpotiFLAC-Extension/main/registry.json',
        'enabled': true,
      },
    ],
  ) as List).whereType<Map>().map(Map.of).toList();
  static Uri indexUri(String input) {
    var uri = Uri.parse(input.trim());
    if (!PublicNetworkClient.publicHttps(uri))
      throw const FormatException('Use a public HTTPS repository index');
    if (uri.host == 'github.com') {
      final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
      if (parts.length == 2 &&
          parts.every((p) => RegExp(r'^[\w.-]+$').hasMatch(p))) {
        final repo = parts[1].replaceFirst(RegExp(r'\.git$'), '');
        uri = Uri.https(
          'api.github.com',
          '/repos/${parts[0]}/$repo/contents/registry.json',
        );
      } else if (parts.length >= 5 && parts[2] == 'blob') {
        uri = Uri.https(
          'raw.githubusercontent.com',
          '/${parts[0]}/${parts[1]}/${parts.skip(3).join('/')}',
        );
      } else {
        throw const FormatException(
          'Use a repository URL or direct registry JSON URL',
        );
      }
    }
    return uri;
  }

  static Future<void> save(String input, {bool enabled = true}) async {
    final url = indexUri(input).toString();
    final items = repositories.where((r) => r['url'] != url).toList();
    if (items.length >= 30)
      throw const FormatException('Maximum 30 repositories');
    items.add({'url': url, 'enabled': enabled});
    await Hive.box('settings').put('sourceRepositories', items);
  }

  static Future<void> remove(String url) => Hive.box('settings').put(
    'sourceRepositories',
    repositories.where((r) => r['url'] != url).toList(),
  );
  Future<List<int>> _bytes(Uri uri, int limit) async {
    final response = await AudioRelayService.instance.open(
      client,
      uri,
      headers: {'Accept': 'application/vnd.github.raw+json'},
      allows: PublicNetworkClient.publicHttps,
    );
    if (response.statusCode != 200) {
      await PublicNetworkClient.cancelBody(response);
      throw const FormatException(
        'Index unavailable. App repositories may not contain registry.json; use an extension repository or direct index URL.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (bytes.length + chunk.length > limit)
        throw const FormatException('Repository response too large');
      bytes.addAll(chunk);
    }
    return bytes;
  }

  static List<SourceRepositoryEntry> parse(List<int> bytes) {
    if (bytes.length > 4 * 1024 * 1024)
      throw const FormatException('Index exceeds 4 MiB');
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map || decoded['extensions'] is! List)
      throw const FormatException('Expected extensions registry');
    final entries = decoded['extensions'] as List;
    if (entries.length > 1000)
      throw const FormatException('Too many catalog entries');
    final ids = <String>{};
    return entries
        .whereType<Map>()
        .where((m) {
          final e = SourceRepositoryEntry(m);
          return e.id.isNotEmpty &&
              e.id.length <= 100 &&
              e.name.length <= 160 &&
              e.description.length <= 4000 &&
              ids.add(e.id);
        })
        .map(SourceRepositoryEntry.new)
        .toList();
  }

  Future<List<int>> fetchExtensionPackage(SourceRepositoryEntry entry) async {
    if (!entry.javascript ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.checksum))
      throw const FormatException(
        'A JavaScript package requires a SHA-256 checksum',
      );
    final bytes = await _bytes(indexUri(entry.downloadUrl), 8 * 1024 * 1024);
    if (sha256.convert(bytes).toString() != entry.checksum)
      throw const FormatException('Extension checksum mismatch');
    return bytes;
  }

  Future<List<SourceRepositoryEntry>> refresh(Map repository) async {
    if (repository['enabled'] != true) throw StateError('Repository disabled');
    return parse(
      await _bytes(indexUri(repository['url'].toString()), 4 * 1024 * 1024),
    );
  }

  Future<FlacExtension> resolve(SourceRepositoryEntry entry) async {
    if (!entry.compatible)
      throw const FormatException(
        'JavaScript runtime is not supported by Yazhal',
      );
    Map manifest;
    if (entry.data['manifest'] is Map) {
      manifest = entry.data['manifest'] as Map;
      if (utf8.encode(jsonEncode(manifest)).length > 65536)
        throw const FormatException('Manifest exceeds 64 KiB');
    } else {
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.checksum))
        throw const FormatException(
          'Remote manifests require a SHA-256 checksum',
        );
      final bytes = await _bytes(indexUri(entry.downloadUrl), 65536);
      if (sha256.convert(bytes).toString() != entry.checksum)
        throw const FormatException('Manifest checksum mismatch');
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map)
        throw const FormatException('Invalid catalog manifest');
      manifest = decoded;
    }
    final extension = FlacExtension.parse(manifest);
    if (extension.id != entry.id)
      throw const FormatException('Catalog identity differs from registry');
    return extension;
  }

  void close() => client.close();
}
