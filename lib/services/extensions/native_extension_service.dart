import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/services/audio_relay_service.dart';
import 'package:yazhal/services/extensions/extension_package.dart';
import 'package:yazhal/services/extensions/extension_runtime.dart';
import 'package:yazhal/services/extensions/extension_state_store.dart';
import 'package:yazhal/services/io_service.dart';
import 'package:yazhal/services/public_network_client.dart';
import 'package:yazhal/utilities/listening_profile.dart';
import 'package:yazhal/utilities/provider_artwork.dart';

const recommendedExtensionRegistry =
    'https://raw.githubusercontent.com/zarzet/SpotiFLAC-Extension/main/registry.json';
bool isNativeExtensionTrack(Map song) => song['source'] == 'js-extension';

class NativeExtensionService {
  NativeExtensionService({this._root, ExtensionStateStore? stateStore})
    : stateStore = stateStore ?? ExtensionStateStore();
  static final instance = NativeExtensionService();
  final Directory? _root;
  final ExtensionStateStore stateStore;
  Directory get root => _root ?? Directory('$applicationDirPath/extensions');
  static List<Map> get installed => (Hive.box('settings').get(
    'javascriptExtensions',
    defaultValue: [],
  ) as List).whereType<Map>().map(Map.of).toList();
  static List<Map> get enabled =>
      installed.where((e) => e['enabled'] == true).toList();
  static List<String> unsupportedFeatures(Map provider) =>
      ((provider['manifest'] as Map?)?['requiredRuntimeFeatures'] as List? ??
              [])
          .whereType<String>()
          .where((feature) => !{'preparedContext@1'}.contains(feature))
          .toList();
  static Future<void> enable(String id, bool value) async {
    final provider = installed.where((p) => p['id'] == id).firstOrNull;
    if (value && provider != null && unsupportedFeatures(provider).isNotEmpty)
      throw StateError(
        'This extension requires ${unsupportedFeatures(provider).join(', ')}. See the source guide; additional native host support is not installed.',
      );
    await Hive.box('settings').put(
      'javascriptExtensions',
      installed
          .map((e) => {...e, if (e['id'] == id) 'enabled': value})
          .toList(),
    );
  }

  Future<ExtensionPackage> inspectPackage(
    String id,
    List<int> bytes,
    String checksum,
  ) => Future.value(ExtensionPackage.decode(id, bytes, checksum));
  Future<void> install(
    ExtensionPackage package,
    List<int> archive, {
    required String repository,
    required String downloadUrl,
  }) async {
    if (sha256.convert(archive).toString() != package.digest)
      throw const FormatException('Archive changed after review');
    if (installed.where((e) => e['id'] != package.id).length >= 100)
      throw const FormatException('Too many installed extensions');
    final directory = Directory('${root.path}/${package.id}/${package.digest}');
    await directory.create(recursive: true);
    final file = File('${directory.path}/package.sflx');
    await file.writeAsBytes(archive, flush: true);
    final record = {
      'id': package.id,
      'name': package.name,
      'version': package.version,
      'author': package.author,
      'homepage': package.manifest['homepage'] ?? '',
      'manifest': package.manifest,
      'digest': package.digest,
      'repository': repository,
      'downloadUrl': downloadUrl,
      'enabled': false,
    };
    await Hive.box('settings').put('javascriptExtensions', [
      ...installed.where((e) => e['id'] != package.id),
      record,
    ]);
  }

  Future<void> uninstall(String id) async {
    if (!RegExp(r'^[a-z][a-z0-9_-]{1,79}$').hasMatch(id))
      throw const FormatException('Invalid extension ID');
    await stateStore.remove(id);
    await Hive.box('settings').put(
      'javascriptExtensions',
      installed.where((e) => e['id'] != id).toList(),
    );
    final directory = Directory('${root.path}/$id');
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<ExtensionPackage> load(String id, {bool requireEnabled = true}) async {
    final record = installed
        .where(
          (e) => e['id'] == id && (!requireEnabled || e['enabled'] == true),
        )
        .firstOrNull;
    if (record == null) throw StateError('Extension is disabled or removed');
    final digest = record['digest'].toString();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        !RegExp(r'^[a-z][a-z0-9_-]{1,79}$').hasMatch(id))
      throw const FormatException('Invalid stored extension identity');
    final file = File('${root.path}/$id/$digest/package.sflx');
    if (await file.length() > 8 * 1024 * 1024)
      throw const FormatException('Stored package exceeds quota');
    return ExtensionPackage.decode(id, await file.readAsBytes(), digest);
  }

  final _pending = <String, Future<void>>{};
  Future<dynamic> call(String id, String method, List args) {
    final next = (_pending[id] ?? Future<void>.value()).then(
      (_) => _call(id, method, args),
    );
    _pending[id] = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }

  Future<dynamic> _call(String id, String method, List args) async {
    final package = await load(id);
    final state = await stateStore.read(id);
    final settings = <String, dynamic>{
      for (final item in package.settings)
        if (item['key'] is String) item['key'].toString(): item['default'],
      ...Map<String, dynamic>.from(state['settings'] as Map? ?? {}),
    };
    if (id == 'jiosaavn' &&
        Hive.box('settings')
                .get('learnListeningLanguage', defaultValue: true) ==
            true) {
      final preference = Hive.box('settings')
          .get('discoveryLanguage', defaultValue: 'automatic')
          .toString();
      final profile = ListeningProfile(
        (Hive.box('user').get('recentlyPlayedSongs', defaultValue: []) as List)
            .whereType<Map>(),
      );
      final language = preference == 'automatic'
          ? profile.language
          : preference;
      settings['lang'] =
          language ?? 'tamil,english,hindi,telugu,malayalam,kannada';
    }
    final required =
        (package.manifest['requiredRuntimeFeatures'] as List? ?? [])
            .whereType<String>()
            .where((f) => !{'preparedContext@1'}.contains(f))
            .toList();
    if (required.isNotEmpty)
      throw StateError(
        'This provider needs additional native runtime support: ${required.join(', ')}. See the source guide.',
      );
    final runtime = ExtensionRuntime();
    try {
      final result = await runtime.call(
        package,
        method,
        args,
        settings: settings,
        storage: Map<String, dynamic>.from(state['storage'] as Map? ?? {}),
      );
      await stateStore.write(id, {
        'settings': state['settings'] ?? {},
        'storage': result.storage,
      });
      return result.value;
    } finally {
      runtime.close();
    }
  }

  Future<List<Map<String, dynamic>>> search(String id, String query) async {
    if (query.trim().isEmpty) return [];
    final value = await call(id, 'searchTracks', [query.trim(), 50]);
    final rows = value is List
        ? value
        : value is Map
        ? value['tracks'] ?? value['items'] ?? []
        : [];
    final seen = <String>{};
    return (rows as List)
        .whereType<Map>()
        .take(100)
        .map((row) => normalizeTrack(id, row))
        .where((row) => seen.add(row['ytid'] as String))
        .toList();
  }

  static Map<String, dynamic> normalizeTrack(String provider, Map raw) {
    final reference = (raw['id'] ?? raw['track_id'] ?? '').toString();
    if (reference.isEmpty || reference.length > 2048)
      throw const FormatException(
        'Provider returned an invalid track identity',
      );
    String artist(Object? value) => value is List
        ? value.map((v) => v is Map ? v['name'] ?? '' : v).join(', ')
        : value is Map
        ? (value['name'] ?? '').toString()
        : value?.toString() ?? '';
    final ytid = 'ext:js:$provider:${sha256.convert(utf8.encode(reference))}';
    final title = (raw['name'] ?? raw['title'] ?? 'Untitled').toString();
    final cover = (raw['cover_url'] ?? raw['image_url'] ?? raw['image'] ?? '')
        .toString();
    return {
      'id': ytid,
      'ytid': ytid,
      'source': 'js-extension',
      'extensionId': provider,
      'providerTrackId': reference,
      'providerTrack': publicProviderMetadata(raw),
      'title': title,
      'artist': artist(raw['artists'] ?? raw['artist'] ?? raw['artist_name']),
      'album': artist(raw['album_name'] ?? raw['album']),
      'language': raw['language'] ?? raw['lang'],
      'duration': raw['duration_ms'] is num
          ? (raw['duration_ms'] as num) / 1000
          : raw['duration'],
      'highResImage': providerArtworkToken(provider, cover),
      'lowResImage': providerArtworkToken(provider, cover),
      'isrc': raw['isrc'],
      'isLive': false,
      'attribution': provider,
    };
  }

  Future<List<ProviderQuality>> qualities(Map song) async =>
      (await load(song['extensionId'].toString())).qualities;
  Future<Map<String, dynamic>> resolve(Map song, {String? quality}) async {
    final id = song['extensionId'].toString();
    final package = await load(id);
    if (!package.types.contains('download_provider'))
      throw StateError(
        'This extension supplies metadata only. Choose an audio source to download.',
      );
    final preferred = Hive.box('settings').get('streamQuality.$id')?.toString();
    final selected =
        quality ??
        (package.qualities.any((q) => q.id == preferred) ? preferred : null) ??
        package.qualities.firstOrNull?.id ??
        'ORIGINAL';
    if (package.qualities.isNotEmpty &&
        !package.qualities.any((q) => q.id == selected))
      throw const FormatException('Quality is not offered by this provider');
    final result = await call(id, 'getDownloadUrl', [
      song['providerTrackId'],
      selected,
      {
        'preparedContext': {'track': song['providerTrack']},
      },
    ]);
    if (result is! Map || result['success'] == false)
      throw StateError(
        result is Map
            ? (result['error_message'] ??
                      result['error'] ??
                      'Provider could not resolve audio')
                  .toString()
            : 'This provider does not expose direct audio URLs. A native transfer or decryption adapter may be required.',
      );
    if (result['decryption'] != null ||
        (result['decryption_key']?.toString().isNotEmpty ?? false) ||
        result['encrypted'] == true ||
        result['requiresDecryption'] == true ||
        result['requires_client_decryption'] == true ||
        result['deezer_encrypted'] == true ||
        result['direct_downloadable'] == false)
      throw StateError(
        'This provider requires an unsupported encrypted transfer',
      );
    final uri = Uri.tryParse(
      (result['url'] ?? result['download_url'] ?? '').toString(),
    );
    if (uri == null || !package.allows(uri))
      throw const FormatException('Audio URL is outside provider permissions');
    final format = (result['actual_extension'] ?? result['format'] ?? '')
        .toString()
        .toLowerCase();
    if (!{
      'mp3',
      'm4a',
      'mp4',
      'aac',
      'flac',
      'ogg',
      'opus',
      'wav',
      'webm',
    }.contains(format))
      throw StateError(
        'Provider did not return a supported direct audio format',
      );
    return Map<String, dynamic>.from(result)
      ..['url'] = uri.toString()
      ..['format'] = format
      ..['selectedQuality'] = selected;
  }

  Future<String?> playbackQuality(Map song, String tier) async {
    final package = await load(song['extensionId'].toString());
    final preferred = Hive.box('settings')
        .get('streamQuality.${song['extensionId']}')
        ?.toString();
    final chosen =
        package.qualities.where((q) => q.id == preferred).firstOrNull ??
        package.qualities.firstOrNull;
    if (chosen == null) return null;
    if (tier == 'high') return chosen.id;
    int bitrate(ProviderQuality q) =>
        int.tryParse(
          RegExp(
                r'(\d+)\s*kbps',
                caseSensitive: false,
              ).firstMatch(q.label)?.group(1) ??
              '',
        ) ??
        0;
    final ceiling = bitrate(chosen);
    if (ceiling == 0) return chosen.id;
    final cap = tier == 'low' ? 96 : 160;
    final alternatives =
        package.qualities
            .where(
              (q) =>
                  bitrate(q) > 0 && bitrate(q) <= cap && bitrate(q) <= ceiling,
            )
            .toList()
          ..sort((a, b) => bitrate(b).compareTo(bitrate(a)));
    return alternatives.firstOrNull?.id ?? chosen.id;
  }

  Future<String> playbackUrl(Map song) async {
    final resolved = await resolve(song);
    song['_extensionHeaders'] = _headers(resolved);
    return resolved['url'].toString();
  }

  static Map<String, String> _headers(Map resolved) => Map<String, String>.from(
    (resolved['headers'] as Map? ?? {}).map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    ),
  );
  Future<void> download(Map song, Map resolved, File target) async {
    final package = await load(song['extensionId'].toString());
    final client = PublicNetworkClient.create();
    final sink = target.openWrite();
    var bytes = 0;
    final prefix = <int>[];
    try {
      final response = await AudioRelayService.instance.open(
        client,
        Uri.parse(resolved['url'].toString()),
        headers: _headers(resolved),
        allows: package.allows,
      );
      if (response.statusCode != 200) {
        await PublicNetworkClient.cancelBody(response);
        throw const HttpException('Provider download failed');
      }
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.startsWith('text/') || contentType.contains('json')) {
        await PublicNetworkClient.cancelBody(response);
        throw const FormatException('Provider returned text instead of audio');
      }
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        prefix.addAll(chunk.take(16 - prefix.length));
        bytes += chunk.length;
        if (bytes > 2 * 1024 * 1024 * 1024)
          throw const FormatException('Audio exceeds 2 GiB');
        if (prefix.length >= 4 &&
            resolved['format'] == 'flac' &&
            utf8.decode(prefix.take(4).toList(), allowMalformed: true) !=
                'fLaC')
          throw const FormatException(
            'Provider did not return FLAC; no lossy relabelling',
          );
        sink.add(chunk);
      }
      if (bytes < 4) throw const FormatException('Empty audio file');
      await sink.flush();
    } finally {
      await sink.close();
      client.close();
    }
  }
}
