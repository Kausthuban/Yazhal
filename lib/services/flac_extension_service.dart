import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;

class FlacExtension {
  FlacExtension({
    required this.id,
    required this.name,
    required this.searchUrl,
    required this.hosts,
    this.enabled = false,
    this.builtIn = false,
  });
  final String id, name, searchUrl;
  final List<String> hosts;
  final bool enabled, builtIn;
  static FlacExtension parse(Map data, {bool installed = false}) {
    final id = data['id']?.toString() ?? '';
    final name = data['name']?.toString().trim() ?? '';
    final url = data['searchUrl']?.toString() ?? '';
    final hosts = (data['allowedHosts'] as List? ?? [])
        .whereType<String>()
        .map((s) => s.toLowerCase())
        .toList();
    if (data['schemaVersion'] != 1 ||
        !RegExp(r'^[a-z][a-z0-9_-]{2,39}$').hasMatch(id) ||
        id == 'archive' ||
        name.isEmpty ||
        name.length > 80 ||
        !url.contains('{query}') ||
        hosts.isEmpty ||
        hosts.length > 10 ||
        hosts.any(
          (h) => !RegExp(r'^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z]{2,}$').hasMatch(h),
        ))
      throw const FormatException('Invalid FLAC extension manifest');
    final extension = FlacExtension(
      id: id,
      name: name,
      searchUrl: url,
      hosts: hosts,
      enabled: installed && data['enabled'] == true,
    );
    if (!extension.allows(Uri.parse(url.replaceAll('{query}', 'test'))))
      throw const FormatException(
        'Search URL must use HTTPS and a declared host',
      );
    return extension;
  }

  bool allows(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      (!uri.hasPort || uri.port == 443) &&
      hosts.any((h) => uri.host == h || (builtIn && uri.host.endsWith('.$h')));
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'name': name,
    'searchUrl': searchUrl,
    'allowedHosts': hosts,
    'enabled': enabled,
  };
}

class FlacExtensionService {
  FlacExtensionService({http.Client? client})
    : client = client ?? http.Client();
  static final instance = FlacExtensionService();
  final http.Client client;
  static List<FlacExtension> get extensions {
    final box = Hive.box('settings');
    return [
      FlacExtension(
        id: 'archive',
        name: 'Live Music Archive',
        searchUrl: 'https://archive.org/advancedsearch.php?q={query}',
        hosts: ['archive.org'],
        builtIn: true,
        enabled: box.get('archiveFlacEnabled', defaultValue: false) == true,
      ),
      ...(box.get('flacExtensions', defaultValue: <dynamic>[]) as List)
          .whereType<Map>()
          .map((m) => FlacExtension.parse(m, installed: true)),
    ];
  }

  static Future<void> install(FlacExtension extension) async {
    final list =
        extensions
            .where((e) => !e.builtIn && e.id != extension.id)
            .map((e) => e.toJson())
            .toList()
          ..add({...extension.toJson(), 'enabled': false});
    await Hive.box('settings').put('flacExtensions', list);
  }

  static Future<void> enable(FlacExtension extension, bool value) async {
    if (extension.builtIn) {
      await Hive.box('settings').put('archiveFlacEnabled', value);
      return;
    }
    await Hive.box('settings').put(
      'flacExtensions',
      extensions
          .where((e) => !e.builtIn)
          .map(
            (e) => {...e.toJson(), if (e.id == extension.id) 'enabled': value},
          )
          .toList(),
    );
  }

  static Future<void> remove(String id) => Hive.box('settings').put(
    'flacExtensions',
    extensions
        .where((e) => !e.builtIn && e.id != id)
        .map((e) => e.toJson())
        .toList(),
  );

  Future<http.StreamedResponse> open(FlacExtension extension, Uri uri) async {
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (!extension.allows(uri))
        throw const FormatException('URL is outside the extension hosts');
      final response = await client
          .send(http.Request('GET', uri)..followRedirects = false)
          .timeout(const Duration(seconds: 25));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        await response.stream.drain<void>();
        if (location == null)
          throw const HttpException('Missing redirect location');
        uri = uri.resolve(location);
      } else {
        return response;
      }
    }
    throw const HttpException('Too many redirects');
  }

  Future<Map> _json(FlacExtension extension, Uri uri) async {
    final response = await open(extension, uri);
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw HttpException('Source unavailable (${response.statusCode})');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 25),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 4 * 1024 * 1024)
        throw const FormatException('Catalog response too large');
    }
    return jsonDecode(utf8.decode(bytes)) as Map;
  }

  static Map<String, dynamic>? track(FlacExtension extension, Map item) {
    final url = Uri.tryParse(item['audioUrl']?.toString() ?? '');
    final title = item['title']?.toString().trim() ?? '';
    if (url == null ||
        !extension.allows(url) ||
        item['format']?.toString().toLowerCase() != 'flac' ||
        title.isEmpty ||
        title.length > 500)
      return null;
    final id =
        'ext:${extension.id}:${sha256.convert(utf8.encode(url.toString()))}';
    return {
      'ytid': id,
      'id': id,
      'source': 'extension',
      'extensionId': extension.id,
      'streamUrl': url.toString(),
      'title': title,
      'artist': item['artist']?.toString() ?? '',
      'album': item['album']?.toString() ?? '',
      'format': 'flac',
      'isLive': false,
      'attribution': item['attribution']?.toString() ?? extension.name,
    };
  }

  Future<List<Map<String, dynamic>>> search(
    FlacExtension extension,
    String query,
  ) async {
    if (!extension.enabled) throw StateError('Enable this source first');
    if (query.trim().isEmpty) return [];
    if (!extension.builtIn) {
      final data = await _json(
        extension,
        Uri.parse(
          extension.searchUrl.replaceAll(
            '{query}',
            Uri.encodeComponent(query.trim()),
          ),
        ),
      );
      return (data['tracks'] as List? ?? [])
          .whereType<Map>()
          .take(100)
          .map((t) => track(extension, t))
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    // Restrict the built-in catalog to recordings in the Live Music Archive.
    final clean = query
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .trim();
    final data = await _json(
      extension,
      Uri.https('archive.org', '/advancedsearch.php', {
        'q': 'collection:etree AND ($clean)',
        'fl[]': 'identifier,title,creator',
        'rows': '4',
        'output': 'json',
      }),
    );
    final result = <Map<String, dynamic>>[];
    for (final item
        in ((data['response'] as Map?)?['docs'] as List? ?? [])
            .whereType<Map>()) {
      final id = item['identifier']?.toString() ?? '';
      if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(id)) continue;
      final metadata = await _json(
        extension,
        Uri.https('archive.org', '/metadata/$id'),
      );
      for (final file in (metadata['files'] as List? ?? []).whereType<Map>()) {
        final name = file['name']?.toString() ?? '';
        if (!name.toLowerCase().endsWith('.flac')) continue;
        final song = track(extension, {
          'audioUrl': Uri(
            scheme: 'https',
            host: 'archive.org',
            pathSegments: ['download', id, ...name.split('/')],
          ).toString(),
          'format': 'flac',
          'title': file['title'] ?? name,
          'artist': item['creator'] is List
              ? (item['creator'] as List).join(', ')
              : item['creator'],
          'album': item['title'],
          'attribution': 'Live Music Archive: $id',
        });
        if (song != null) result.add(song);
        if (result.length >= 80) return result;
      }
    }
    return result;
  }

  static FlacExtension sourceFor(Map song) =>
      extensions
          .where((e) => e.id == song['extensionId'] && e.enabled)
          .firstOrNull ??
      (throw StateError('FLAC source disabled or removed'));
  static bool flacMagic(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x66 &&
      bytes[1] == 0x4c &&
      bytes[2] == 0x61 &&
      bytes[3] == 0x43;
  Future<void> download(Map song, File target) async {
    final extension = sourceFor(song);
    final response = await open(
      extension,
      Uri.parse(song['streamUrl'].toString()),
    );
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw HttpException('FLAC download failed (${response.statusCode})');
    }
    final sink = target.openWrite();
    final prefix = <int>[];
    var count = 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 40),
      )) {
        prefix.addAll(chunk.take(4 - prefix.length));
        count += chunk.length;
        if (prefix.length == 4 && !flacMagic(prefix))
          throw const FormatException('Source did not return a FLAC file');
        if (count > 2 * 1024 * 1024 * 1024)
          throw const FormatException('FLAC download exceeds 2 GiB');
        sink.add(chunk);
      }
      if (!flacMagic(prefix))
        throw const FormatException('Incomplete FLAC file');
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<String> playbackUrl(Map song) async {
    final source = sourceFor(song);
    final response = await open(
      source,
      Uri.parse(song['streamUrl'].toString()),
    );
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw const HttpException('FLAC source unavailable');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      bytes.addAll(chunk.take(4 - bytes.length));
      if (bytes.length >= 4) break;
    }
    if (!flacMagic(bytes))
      throw const FormatException('Source did not return FLAC');
    // Play the final validated URL so the engine need not repeat the redirect chain.
    return response.request?.url.toString() ?? song['streamUrl'].toString();
  }
}
