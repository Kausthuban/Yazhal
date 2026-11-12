import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:yazhal/services/common_services.dart' show userOfflineSongs;
import 'package:yazhal/services/io_service.dart' show applicationDirPath;
import 'package:yazhal/services/music_storage_service.dart';

class MetadataCandidate {
  MetadataCandidate({
    required this.title,
    required this.artist,
    required this.album,
    required this.recordingId,
    required this.releaseId,
  });
  final String title, artist, album, recordingId;
  final String? releaseId;
  static bool validId(String id) => RegExp(
    r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(id);
  static List<MetadataCandidate> parse(
    Map data,
  ) => (data['recordings'] as List? ?? [])
      .whereType<Map>()
      .where((r) => validId(r['id']?.toString() ?? ''))
      .map((r) {
        final release = (r['releases'] as List? ?? [])
            .whereType<Map>()
            .firstOrNull;
        final releaseId = release?['id']?.toString();
        return MetadataCandidate(
          title: r['title']?.toString() ?? '',
          artist: (r['artist-credit'] as List? ?? [])
              .whereType<Map>()
              .map(
                (a) =>
                    '${a['name'] ?? (a['artist'] as Map?)?['name'] ?? ''}${a['joinphrase'] ?? ''}',
              )
              .join(),
          album: release?['title']?.toString() ?? '',
          recordingId: r['id'].toString(),
          releaseId: releaseId != null && validId(releaseId) ? releaseId : null,
        );
      })
      .where((c) => c.title.isNotEmpty)
      .take(8)
      .toList();
}

class OfflineMetadataService {
  OfflineMetadataService({
    http.Client? client,
    this.spacing = const Duration(milliseconds: 1100),
  }) : client = client ?? http.Client();
  static final instance = OfflineMetadataService();
  final http.Client client;
  final Duration spacing;
  Future<void> _requests = Future.value();
  final _cache = <String, List<MetadataCandidate>>{};
  static bool get enabled =>
      Hive.box('settings').get('onlineOfflineMetadata', defaultValue: false) ==
      true;
  static String query(Map song) {
    var title = (song['title'] ?? '').toString().trim();
    var artist = (song['artist'] ?? '').toString().trim();
    if (artist.isEmpty && title.contains(' - ')) {
      final parts = title.split(' - ');
      artist = parts.first;
      title = parts.skip(1).join(' - ');
    }
    String escape(String s) =>
        s.replaceAll(RegExp(r'[+\-!(){}\[\]^"~*?:\\/]'), ' ').trim();
    return 'recording:"${escape(title)}"${artist.isEmpty ? '' : ' AND artist:"${escape(artist)}"'}';
  }

  Future<List<MetadataCandidate>> search(Map song) {
    final q = query(song);
    final result = _requests.then((_) async {
      if (_cache.containsKey(q)) return _cache[q]!;
      try {
        final response = await client
            .get(
              Uri.https('musicbrainz.org', '/ws/2/recording/', {
                'query': q,
                'fmt': 'json',
                'limit': '8',
              }),
              headers: {
                'User-Agent':
                    'Yazhal/10.6.3 (https://github.com/Kausthuban/Yazhal)',
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200)
          throw HttpException(
            'MusicBrainz unavailable (${response.statusCode}). Try again later.',
          );
        final candidates = MetadataCandidate.parse(
          jsonDecode(response.body) as Map,
        );
        if (_cache.length >= 100) _cache.remove(_cache.keys.first);
        return _cache[q] = candidates;
      } finally {
        await Future<void>.delayed(spacing);
      }
    });
    _requests = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<({bool artwork, bool missingArtwork})> apply(
    String id,
    MetadataCandidate candidate,
  ) async {
    String? path;
    if (candidate.releaseId != null) {
      try {
        final request = http.Request(
          'GET',
          Uri.https(
            'coverartarchive.org',
            '/release/${candidate.releaseId}/front-500',
          ),
        );
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) {
          final bytes = <int>[];
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 20),
          )) {
            bytes.addAll(chunk);
            if (bytes.length > 6 * 1024 * 1024)
              throw const FormatException('Artwork too large');
          }
          final image =
              bytes.length >= 12 &&
              ((bytes[0] == 0xff && bytes[1] == 0xd8) ||
                  (bytes[0] == 0x89 && bytes[1] == 0x50) ||
                  (ascii.decode(bytes.take(4).toList(), allowInvalid: true) ==
                          'RIFF' &&
                      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) ==
                          'WEBP'));
          if (!image) throw const FormatException('Unsupported artwork');
          final dir = await Directory('$applicationDirPath/offline_art')
              .create(recursive: true);
          final safeId = MusicStorageService.localId(id).substring(6);
          final file = File('${dir.path}/$safeId-${candidate.releaseId}.jpg');
          final partial = File('${file.path}.partial');
          await partial.writeAsBytes(bytes, flush: true);
          await partial.rename(file.path);
          path = file.path;
        } else {
          await response.stream.drain<void>();
        }
      } catch (_) {
        /* Artwork unavailable must not prevent a confirmed metadata edit. */
      }
    }
    await MusicStorageService.mutateOfflineSongs(
      (songs) => songs
          .map(
            (s) => s['ytid'] == id
                ? <String, dynamic>{
                    ...Map<String, dynamic>.from(s as Map),
                    'title': candidate.title,
                    'artist': candidate.artist,
                    'album': candidate.album,
                    'metadataSource': 'MusicBrainz',
                    'recordingId': candidate.recordingId,
                    'releaseId': candidate.releaseId,
                    if (path != null) 'artworkPath': path,
                  }
                : s,
          )
          .toList(),
      onSaved: (songs) => userOfflineSongs.value = songs,
    );
    return (artwork: path != null, missingArtwork: path == null);
  }
}
