import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:yazhal/services/public_network_client.dart';

bool isYoutubeArtwork(String value) {
  final host = Uri.tryParse(value)?.host.toLowerCase() ?? '';
  return [
    'ytimg.com',
    'youtube.com',
    'ggpht.com',
    'yt3.googleusercontent.com',
  ].any((h) => host == h || host.endsWith('.$h'));
}

String cleanArtwork(Object? value) {
  final text = value?.toString() ?? '';
  return isYoutubeArtwork(text) ? '' : text;
}

/// Public Apple/iTunes catalogue metadata, not Apple Music audio or a DRM SDK.
/// Lookups run after playback starts; visible rows never queue network searches.
class CatalogMetadataService {
  CatalogMetadataService({
    http.Client? client,
    this.spacing = const Duration(milliseconds: 1600),
  }) : client = client ?? PublicNetworkClient.create();
  static final instance = CatalogMetadataService();
  final http.Client client;
  final Duration spacing;
  final _pending = <String, Future<Map<String, dynamic>>>{};
  Future<void> _tail = Future.value();
  static Set<String> _words(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .split(' ')
      .where((s) => s.length > 1)
      .toSet();
  static double similarity(String a, String b) {
    final x = _words(a), y = _words(b);
    if (x.isEmpty || y.isEmpty) return 0;
    return x.intersection(y).length /
        (x.length < y.length ? x.length : y.length);
  }

  static Map<String, dynamic> match(Map song, List rows) {
    Map? best;
    var score = 0.0;
    for (final row in rows.whereType<Map>()) {
      final title = similarity(
        '${song['title'] ?? ''}',
        '${row['trackName'] ?? ''}',
      );
      final artist = similarity(
        '${song['artist'] ?? ''}',
        '${row['artistName'] ?? ''}',
      );
      if (title < .6 || artist < .5) continue;
      final duration = song['duration'];
      final millis = row['trackTimeMillis'];
      if (duration is num &&
          millis is num &&
          duration > 0 &&
          (duration - millis / 1000).abs() > 15)
        continue;
      if (title + artist > score) {
        score = title + artist;
        best = row;
      }
    }
    if (best == null) return {};
    final raw = best['artworkUrl100']?.toString() ?? '';
    final uri = Uri.tryParse(raw);
    final cover =
        uri != null &&
            uri.scheme == 'https' &&
            (uri.host == 'mzstatic.com' ||
                uri.host.endsWith('.mzstatic.com')) &&
            uri.userInfo.isEmpty
        ? raw.replaceAll(RegExp(r'/\d+x\d+bb\.'), '/600x600bb.')
        : '';
    return {
      if (cover.isNotEmpty) 'catalogArtwork': cover,
      'catalogAlbum': best['collectionName']?.toString() ?? '',
      'catalogGenre': best['primaryGenreName']?.toString() ?? '',
      'catalogAttribution': 'Apple iTunes Search API',
    };
  }

  Future<Map<String, dynamic>> lookup(Map song) {
    final title = song['title']?.toString() ?? '',
        artist = song['artist']?.toString() ?? '';
    if (title.isEmpty || artist.isEmpty) return Future.value({});
    final key = sha256.convert(utf8.encode('$artist|$title')).toString();
    final cached = Hive.box('cache').get('catalogue.$key');
    if (cached is Map &&
        (cached['expires'] as int? ?? 0) >
            DateTime.now().millisecondsSinceEpoch)
      return Future.value(Map<String, dynamic>.from(cached['data'] as Map));
    if (_pending.containsKey(key)) return _pending[key]!;
    if (_pending.length >= 8) return Future.value({});
    final future = _tail.then((_) async {
      try {
        final q = '$artist $title';
        final response = await client
            .get(
              Uri.https('itunes.apple.com', '/search', {
                'term': q.substring(0, q.length.clamp(0, 512)),
                'entity': 'song',
                'country': 'IN',
                'limit': '5',
              }),
            )
            .timeout(const Duration(seconds: 6));
        if (response.statusCode != 200 ||
            response.bodyBytes.length > 512 * 1024)
          return <String, dynamic>{};
        final result = match(
          song,
          (jsonDecode(response.body) as Map)['results'] as List? ?? [],
        );
        await Hive.box('cache').put('catalogue.$key', {
          'expires': DateTime.now()
              .add(Duration(hours: result.isEmpty ? 1 : 168))
              .millisecondsSinceEpoch,
          'data': result,
        });
        return result;
      } catch (_) {
        return <String, dynamic>{};
      } finally {
        await Future<void>.delayed(spacing);
      }
    });
    _tail = future.then<void>((_) {}, onError: (Object _) {});
    _pending[key] = future;
    return future.whenComplete(() => _pending.remove(key));
  }
}
