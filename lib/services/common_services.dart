/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Yazhal is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Yazhal is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Yazhal, including how to contribute,
 *     please visit: https://github.com/Kausthuban/Yazhal
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:yazhal/constants/clients.dart';
import 'package:yazhal/main.dart' show logger;
import 'package:yazhal/services/data_manager.dart';
import 'package:yazhal/services/flac_extension_service.dart';
import 'package:yazhal/services/io_service.dart';
import 'package:yazhal/services/lyrics_manager.dart';
import 'package:yazhal/services/music_storage_service.dart';
import 'package:yazhal/services/offline_taste_service.dart';
import 'package:yazhal/services/playlists_manager.dart';
import 'package:yazhal/services/proxy_manager.dart';
import 'package:yazhal/services/settings_manager.dart';
import 'package:yazhal/utilities/app_utils.dart';
import 'package:yazhal/utilities/formatter.dart';
import 'package:yazhal/utilities/local_tracks.dart';
import 'package:yazhal/utilities/map_utils.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

List globalSongs = [];

ValueNotifier<List> userLikedSongsList = ValueNotifier<List>(
  Hive.box('user').get('likedSongs', defaultValue: []),
);

ValueNotifier<List<String>> userLikedRadioStations =
    ValueNotifier<List<String>>(
      List<String>.from(
        Hive.box('user').get('likedRadioStations', defaultValue: []),
      ),
    );

ValueNotifier<List> userRecentlyPlayed = ValueNotifier<List>(
  Hive.box('user').get('recentlyPlayedSongs', defaultValue: []),
);
ValueNotifier<List> userOfflineSongs = ValueNotifier<List>(
  Hive.box('userNoBackup').get('offlineSongs', defaultValue: []),
);

Set<String> _createSongIdCache(ValueNotifier<List> source) {
  final cache = _songIds(source.value);

  source.addListener(() {
    cache
      ..clear()
      ..addAll(_songIds(source.value));
  });

  return cache;
}

Set<String> _songIds(Iterable songs) =>
    songs.whereType<Map>().map(songYtid).whereType<String>().toSet();

final _cachedLikedSongIds = _createSongIdCache(userLikedSongsList);
final _cachedOfflineSongIds = _createSongIdCache(userOfflineSongs);

var _songLikeUpdateToken = 0;
final _latestSongLikeUpdateTokens = <String, int>{};

final lyrics = ValueNotifier<String?>(null);
String? lastFetchedLyrics;

void reloadSongLibraryStateFromStorage() {
  final userBox = Hive.box('user');
  userLikedRadioStations.value = List<String>.from(
    userBox.get('likedRadioStations', defaultValue: []),
  );
  userLikedSongsList.value = List.from(
    userBox.get('likedSongs', defaultValue: []),
  );
  userRecentlyPlayed.value = List.from(
    userBox.get('recentlyPlayedSongs', defaultValue: []),
  );
}

// Timeouts and durations used across manifest fetching and cache validation.
const Duration _manifestTimeout = Duration(seconds: 30);
const Duration _cacheValidationDuration = Duration(hours: 1);

/// Fetches a stream manifest for a song, honoring proxy settings.
Future<StreamManifest?> _fetchStreamManifest(String songId) async {
  if (useProxy.value) {
    return ProxyManager().getSongManifest(songId).timeout(_manifestTimeout);
  }

  try {
    return await getManifestWithFallback(
      ytClient,
      songId,
      timeout: _manifestTimeout,
    );
  } on Exception catch (error, stackTrace) {
    logger.log(
      'Direct stream lookup failed for $songId; trying proxy fallback',
      error: error,
      stackTrace: stackTrace,
    );
    final manifest = await ProxyManager()
        .getSongManifestViaProxy(songId)
        .timeout(_manifestTimeout);
    if (manifest != null) return manifest;
    Error.throwWithStackTrace(error, stackTrace);
  }
}

/// Returns a cached song URL if present and still valid.
Future<String?> _getCachedSongUrl(
  String songId,
  String cacheKey,
  Duration cacheDuration,
) async {
  final cachedUrl = await getData(
    'cache',
    cacheKey,
    cachingDuration: cacheDuration,
  );

  if (cachedUrl is! String || cachedUrl.isEmpty) {
    return null;
  }

  final cacheBox = await Hive.openBox('cache');
  final cacheDate = cacheBox.get('${cacheKey}_date') as DateTime?;
  final now = DateTime.now();
  final isOld =
      cacheDate != null && now.difference(cacheDate) > _cacheValidationDuration;

  if (!isOld) {
    return cachedUrl;
  }

  if (await _validateCachedUrl(songId, cachedUrl)) {
    return cachedUrl;
  }

  await deleteData('cache', cacheKey);
  await deleteData('cache', '${cacheKey}_date');
  return null;
}

/// Checks if a cached URL still responds successfully.
Future<bool> _validateCachedUrl(String songId, String cachedUrl) async {
  try {
    final response = await http.head(
      Uri.parse(cachedUrl),
      headers: streamPlaybackHeaders(songId),
    );
    return response.statusCode >= 200 && response.statusCode < 300;
  } catch (_) {
    return false;
  }
}

Future<List> fetchSongsList(String searchQuery) async {
  try {
    // If not in cache, perform the search
    final List<Video> searchResults = await ytClient.search.search(searchQuery);
    final songsList = searchResults
        .map((video) => returnSongLayout(0, video))
        .toList();

    return songsList;
  } catch (e, stackTrace) {
    logger.log('Error in fetchSongsList', error: e, stackTrace: stackTrace);
    return [];
  }
}

final _offlineDiscoveryCache = <String, ({DateTime time, List songs})>{};
Future<List> _discoverOfflineQuery(String query) async {
  final cached = _offlineDiscoveryCache[query];
  if (cached != null &&
      DateTime.now().difference(cached.time) < const Duration(minutes: 15))
    return cached.songs;
  final songs = await fetchSongsList(query);
  if (_offlineDiscoveryCache.length >= 30)
    _offlineDiscoveryCache.remove(_offlineDiscoveryCache.keys.first);
  _offlineDiscoveryCache[query] = (time: DateTime.now(), songs: songs);
  return songs;
}

Future<List> getRecommendedSongs({
  Set<String> excludedIds = const {},
  bool forceRefresh = false,
}) async {
  final local = userOfflineSongs.value.whereType<Map>().toList();
  final profile = OfflineTasteService.profile(local);
  if (offlineMode.value) {
    final songs = OfflineTasteService.enabled
        ? profile.rank(local, local: true)
        : (local..shuffle());
    return songs
        .where((s) => !excludedIds.contains(s['ytid']?.toString()))
        .take(15)
        .toList();
  }
  final results = <Map>[];
  if (OfflineTasteService.enabled && externalRecommendations.value) {
    // Resolve descriptive local metadata to real provider records, never local IDs.
    for (final query in profile.discoveryQueries) {
      results.addAll(
        (await _discoverOfflineQuery(query)).whereType<Map>().take(8),
      );
    }
  }
  try {
    final base =
        externalRecommendations.value &&
            userRecentlyPlayed.value.whereType<Map>().any(
              (s) => !isLocalTrack(s) && !isExtensionTrack(s),
            )
        ? await _getRecommendationsFromRecentlyPlayed()
        : await _getRecommendationsFromMixedSources(excludedIds: excludedIds);
    results.addAll(base.whereType<Map>());
  } catch (e, stackTrace) {
    logger.log(
      'Recommendation source unavailable',
      error: e,
      stackTrace: stackTrace,
    );
    if (results.isEmpty && local.isEmpty && forceRefresh) rethrow;
  }
  if (results.isEmpty) results.addAll(local);
  final unique = <String>{...excludedIds};
  final ranked = OfflineTasteService.enabled
      ? profile.rank(results)
      : (results..shuffle());
  return ranked
      .where((s) => unique.add(s['ytid'].toString()))
      .take(15)
      .toList();
}

Future<List> _getRecommendationsFromRecentlyPlayed() async {
  final recent = (List.from(
    userRecentlyPlayed.value,
  )..shuffle()).take(5).toList();

  return _getRecommendationsFromSeedSongs(recent);
}

/// Expands seed songs into related videos and ranks them for home and playlist recommendations.
Future<List> _getRecommendationsFromSeedSongs(List seedSongs) async {
  final seeds = seedSongs
      .whereType<Map>()
      .where(
        (song) =>
            !isLocalTrack(song) &&
            !isExtensionTrack(song) &&
            (song['ytid']?.toString() ?? '').isNotEmpty,
      )
      .toList();
  if (seeds.isEmpty) return [];

  var successfulSeeds = 0;
  final scores = <String, double>{};
  final songMap = <String, Map>{};

  final futures = seeds.asMap().entries.map((entry) async {
    final seedIndex = entry.key;
    final songData = entry.value;
    try {
      final song = await ytClient.videos.get(songData['ytid']);
      final related = await ytClient.videos.getRelatedVideos(song) ?? [];
      successfulSeeds++;
      for (var i = 0; i < related.length && i < 8; i++) {
        final s = returnSongLayout(0, related[i]);
        final id = s['ytid'];
        final positionWeight = 1.0 - (i / 8);
        final recencyWeight = 1.0 - (seedIndex / seeds.length);
        scores[id] = (scores[id] ?? 0) + positionWeight * recencyWeight;
        songMap[id] = s;
      }
    } catch (e, st) {
      logger.log(
        'related videos error for ${songData['ytid']}',
        error: e,
        stackTrace: st,
      );
    }
  }).toList();

  await Future.wait(futures);

  if (successfulSeeds == 0)
    throw StateError('No recommendation seed could be loaded');
  final sorted = scores.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.map((e) => songMap[e.key]!).toList();
}

/// Number of playlist tracks used to seed recommendations while keeping network cost bounded.
const _playlistRecommendationSeedCount = 5;

/// In-memory recommendations cache keyed by playlist ytid and cleared on app restart.
final Map<String, List> _playlistRecommendationsCache = {};

/// Gets playlist-seeded recommendations, reusing cached results and returning an empty list on failure.
Future<List> getRecommendedSongsForPlaylist(
  String playlistId,
  List playlistSongs, {
  bool forceRefresh = false,
  Set<String> excludedIds = const {},
}) async {
  try {
    final existingIds = playlistSongs
        .whereType<Map>()
        .map((song) => song['ytid']?.toString())
        .toSet();

    if (offlineMode.value) {
      return OfflineTasteService.profile(
            userOfflineSongs.value.whereType<Map>(),
          )
          .rank(userOfflineSongs.value.whereType<Map>(), local: true)
          .where(
            (s) =>
                !existingIds.contains(s['ytid']) &&
                !excludedIds.contains(s['ytid']),
          )
          .take(15)
          .toList();
    }
    final cached = _playlistRecommendationsCache[playlistId];
    if (cached != null && !forceRefresh) {
      final stillFresh = cached
          .where(
            (song) =>
                !existingIds.contains(song['ytid']?.toString()) &&
                !excludedIds.contains(song['ytid']?.toString()),
          )
          .toList();
      if (stillFresh.isNotEmpty) return stillFresh;
    }

    final seeds = _sampleSeedSongs(
      playlistSongs,
      _playlistRecommendationSeedCount,
    );
    if (seeds.isEmpty &&
        OfflineTasteService.enabled &&
        externalRecommendations.value) {
      for (final query in OfflineTasteProfile(
        playlistSongs.whereType<Map>(),
        OfflineTasteService.history,
      ).discoveryQueries.take(2)) {
        seeds.addAll(
          (await _discoverOfflineQuery(query)).whereType<Map>().take(1),
        );
      }
    }
    final recommendations = await _getRecommendationsFromSeedSongs(seeds);
    final filtered = recommendations
        .where(
          (song) =>
              !existingIds.contains(song['ytid']?.toString()) &&
              !excludedIds.contains(song['ytid']?.toString()),
        )
        .toList();

    _playlistRecommendationsCache[playlistId] = filtered;
    return filtered;
  } catch (e, stackTrace) {
    logger.log(
      'Error in getRecommendedSongsForPlaylist',
      error: e,
      stackTrace: stackTrace,
    );
    if (forceRefresh) rethrow;
    return [];
  }
}

/// Uniformly samples up to [count] valid songs in one pass without copying or shuffling the playlist.
List<Map> _sampleSeedSongs(List songs, int count) {
  final random = Random();
  final reservoir = <Map>[];
  var seen = 0;

  for (final song in songs) {
    if (song is! Map ||
        isLocalTrack(song) ||
        isExtensionTrack(song) ||
        (song['ytid']?.toString() ?? '').isEmpty)
      continue;
    seen++;
    if (reservoir.length < count) {
      reservoir.add(song);
    } else {
      final slot = random.nextInt(seen);
      if (slot < count) reservoir[slot] = song;
    }
  }

  return reservoir;
}

Future<List> _getRecommendationsFromMixedSources({
  Set<String> excludedIds = const {},
}) async {
  final recommendationSources = <Iterable<dynamic>>[
    userLikedSongsList.value,
    userRecentlyPlayed.value,
  ];

  if (globalSongs.isEmpty) {
    const playlistId = 'PLgzTt0k8mXzEk586ze4BjvDXR7c-TUSnx';
    globalSongs = await getSongsFromPlaylist(playlistId);
  }
  recommendationSources.add(globalSongs);

  if (userCustomPlaylists.value.isNotEmpty) {
    for (final userPlaylist in userCustomPlaylists.value) {
      final playlistSongs = userPlaylist['list'] as List;
      recommendationSources.add(_sampleSeedSongs(playlistSongs, 5));
    }
  }

  return sampleUniqueSongs(
    recommendationSources.map(
      (source) => source.where(
        (s) => s is Map && !excludedIds.contains(s['ytid']?.toString()),
      ),
    ),
    15,
  );
}

Future<void> updateSongLikeStatus(
  dynamic songId,
  bool add, {
  Map? songData,
}) async {
  try {
    final normalizedSongId = songId?.toString().trim() ?? '';
    if (normalizedSongId.isEmpty) return;

    final updateToken = ++_songLikeUpdateToken;
    _latestSongLikeUpdateTokens[normalizedSongId] = updateToken;

    final songToAdd = add
        ? await _resolveSongForLikedStatus(normalizedSongId, songData)
        : null;

    if (_latestSongLikeUpdateTokens[normalizedSongId] != updateToken) {
      return;
    }

    final updatedLikedSongs = _deduplicateLikedSongs(userLikedSongsList.value);

    if (add) {
      if (songToAdd != null &&
          !updatedLikedSongs.any(
            (song) => song['ytid']?.toString() == normalizedSongId,
          )) {
        updatedLikedSongs.insert(0, songToAdd);
      }
    } else {
      updatedLikedSongs.removeWhere(
        (song) => song['ytid']?.toString() == normalizedSongId,
      );
    }

    if (_likedSongIdsAreEqual(userLikedSongsList.value, updatedLikedSongs))
      return;

    userLikedSongsList.value = updatedLikedSongs;
    unawaited(
      addOrUpdateData<List>('user', 'likedSongs', userLikedSongsList.value),
    );
  } catch (e, stackTrace) {
    logger.log(
      'Error updating song like status',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

Future<Map?> _resolveSongForLikedStatus(String songId, Map? songData) async {
  if (songData?['ytid']?.toString() == songId) {
    return Map<String, dynamic>.from(songData!);
  }

  final cachedSong = findSongByYtid(userLikedSongsList.value, songId);
  if (cachedSong != null) return Map<String, dynamic>.from(cachedSong);

  return getSongDetails(userLikedSongsList.value.length, songId);
}

List _deduplicateLikedSongs(Iterable<dynamic> likedSongs) {
  final seenSongIds = <String>{};
  final deduplicatedSongs = [];

  for (final song in likedSongs) {
    if (song is! Map) {
      deduplicatedSongs.add(song);
      continue;
    }

    final songId = song['ytid']?.toString();
    if (songId == null || songId.isEmpty || isLocalTrackId(songId)) {
      deduplicatedSongs.add(song);
      continue;
    }

    if (seenSongIds.add(songId)) {
      deduplicatedSongs.add(song);
    }
  }

  return deduplicatedSongs;
}

bool _likedSongIdsAreEqual(List previous, List updated) {
  if (previous.length != updated.length) return false;

  for (var i = 0; i < previous.length; i++) {
    final previousSong = previous[i];
    final updatedSong = updated[i];
    if (previousSong is! Map || updatedSong is! Map) {
      if (previousSong != updatedSong) return false;
      continue;
    }

    if (previousSong['ytid']?.toString() != updatedSong['ytid']?.toString()) {
      return false;
    }
  }

  return true;
}

Future<void> renameSongInLikedSongs(
  dynamic songId,
  String newTitle,
  String newArtist,
) async {
  try {
    final songIndex = userLikedSongsList.value.indexWhere(
      (song) => song['ytid'] == songId,
    );

    if (songIndex != -1) {
      final updatedList = List.from(userLikedSongsList.value);
      updatedList[songIndex] = Map.from(updatedList[songIndex] as Map)
        ..['title'] = newTitle
        ..['artist'] = newArtist;
      userLikedSongsList.value = updatedList;

      unawaited(
        addOrUpdateData<List>('user', 'likedSongs', userLikedSongsList.value),
      );
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error renaming song in liked songs',
      error: e,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}

bool isSongAlreadyLiked(songIdToCheck) {
  final songId = songIdToCheck?.toString();
  return songId != null && _cachedLikedSongIds.contains(songId);
}

bool isPlaylistAlreadyLiked(playlistIdToCheck) {
  final playlistId = playlistIdToCheck?.toString();
  if (playlistId == null || playlistId.isEmpty) return false;
  return userLikedPlaylists.value.any(
    (playlist) => playlist['ytid']?.toString() == playlistId,
  );
}

bool isRadioStationLiked(String radioStationId) {
  return userLikedRadioStations.value.contains(radioStationId);
}

Future<void> addRadioStationToLiked(String radioStationId) async {
  if (!userLikedRadioStations.value.contains(radioStationId)) {
    final updatedList = List<String>.from(userLikedRadioStations.value)
      ..add(radioStationId);
    userLikedRadioStations.value = updatedList;
    await addOrUpdateData<List<String>>(
      'user',
      'likedRadioStations',
      updatedList,
    );
  }
}

Future<void> removeRadioStationFromLiked(String radioStationId) async {
  if (userLikedRadioStations.value.contains(radioStationId)) {
    final updatedList = List<String>.from(userLikedRadioStations.value)
      ..remove(radioStationId);
    userLikedRadioStations.value = updatedList;
    unawaited(
      addOrUpdateData<List<String>>('user', 'likedRadioStations', updatedList),
    );
  }
}

bool isSongAlreadyOffline(songIdToCheck) {
  final songId = songIdToCheck?.toString();
  return songId != null && _cachedOfflineSongIds.contains(songId);
}

bool isPlaylistFullyOffline(List songs) {
  if (songs.isEmpty) return false;
  final offlineIds = userOfflineSongs.value.map((s) => s['ytid']).toSet();
  return songs.every((s) => offlineIds.contains(s['ytid']));
}

Map<String, dynamic> getOfflineSongByYtid(String ytid) {
  try {
    final song = userOfflineSongs.value.firstWhere(
      (s) => s['ytid'] == ytid,
      orElse: () => <String, dynamic>{},
    );
    return Map<String, dynamic>.from(song);
  } catch (_) {
    return <String, dynamic>{};
  }
}

Future<List<String>> getSearchSuggestions(String query) async {
  // Custom implementation:

  // const baseUrl = 'https://suggestqueries.google.com/complete/search';
  // final parameters = {
  //   'client': 'firefox',
  //   'ds': 'yt',
  //   'q': query,
  // };

  // final uri = Uri.parse(baseUrl).replace(queryParameters: parameters);

  // try {
  //   final response = await http.get(
  //     uri,
  //     headers: {
  //       'User-Agent':
  //           'Mozilla/5.0 (Windows NT 10.0; rv:96.0) Gecko/20100101 Firefox/96.0',
  //     },
  //   );

  //   if (response.statusCode == 200) {
  //     final suggestions = jsonDecode(response.body)[1] as List<dynamic>;
  //     final suggestionStrings = suggestions.cast<String>().toList();
  //     return suggestionStrings;
  //   }
  // } catch (e, stackTrace) {
  //   logger.log('Error in getSearchSuggestions:$e\n$stackTrace');
  // }

  // Built-in implementation:

  final suggestions = await ytClient.search.getQuerySuggestions(query);

  return suggestions;
}

// Throws on network, HTTP and parsing failure instead of swallowing it, so
// callers that need to tell "confirmed no segments" apart from "failed to
// fetch" (e.g. the offline cache, which must not persist a false negative)
// can do so.
Future<List<Map<String, int>>> _fetchSkipSegments(String id) async {
  final res = await ProxyManager().getProxiedResponse(
    Uri(
      scheme: 'https',
      host: 'sponsor.ajay.app',
      path: '/api/skipSegments',
      queryParameters: {
        'videoID': id,
        'category': [
          'sponsor',
          'selfpromo',
          'interaction',
          'intro',
          'outro',
          'music_offtopic',
        ],
        'actionType': 'skip',
      },
    ),
  );
  // 404 is how the API answers "this video has no segments", so it is a real
  // empty result and safe to remember. Any other non-200 is a failure, and
  // throwing keeps it from being stored as a confirmed "no segments".
  if (res.statusCode == 404 || res.body == 'Not Found') return [];
  if (res.statusCode != 200) {
    throw HttpException('SponsorBlock responded ${res.statusCode} for $id');
  }

  final data = jsonDecode(res.body);
  final segments = data.map((obj) {
    return Map.castFrom<String, dynamic, String, int>({
      'start': obj['segment'].first.toInt(),
      'end': obj['segment'].last.toInt(),
    });
  }).toList();
  return List.castFrom<dynamic, Map<String, int>>(segments);
}

Future<List<Map<String, int>>> getSkipSegments(String id) async {
  try {
    return await _fetchSkipSegments(id);
  } catch (e, stackTrace) {
    logger.log('Error in getSkipSegments', error: e, stackTrace: stackTrace);
    return [];
  }
}

/// The first song related to [songYtId] whose ytid is not in [excludedYtIds].
Future<Map<String, dynamic>?> getSimilarSong(
  String songYtId, {
  Set<String> excludedYtIds = const {},
}) async {
  if (isNonYoutubeId(songYtId)) return null;
  try {
    final song = await ytClient.videos.get(songYtId);
    final relatedSongs = await ytClient.videos.getRelatedVideos(song) ?? [];

    for (final video in relatedSongs) {
      final candidate = returnSongLayout(0, video);
      if (!excludedYtIds.contains(candidate['ytid']?.toString())) {
        return candidate;
      }
    }
    logger.log('No new related songs found for $songYtId');
  } catch (e, stackTrace) {
    logger.log(
      'Error while fetching next similar song:',
      error: e,
      stackTrace: stackTrace,
    );
  }
  return null;
}

/// In-memory cache of the audio stream picked for a song at the current
/// quality setting. The Hive cache only keeps the URL, so without this every
/// caller that needs the stream itself (bitrate, codec) would fetch the
/// manifest again right after playback already resolved it.
final Map<String, ({AudioOnlyStreamInfo stream, DateTime resolvedAt})>
_selectedAudioStreams = {};

const _maxSelectedAudioStreams = 50;

String _selectedAudioStreamKey(String songId) =>
    '${songId}_${audioQualitySetting.value}';

/// Returns the stream resolved earlier for a song, unless it is old enough
/// that its URL may have expired.
AudioOnlyStreamInfo? _getSelectedAudioStream(String songId) {
  final key = _selectedAudioStreamKey(songId);
  final entry = _selectedAudioStreams[key];
  if (entry == null) return null;

  if (DateTime.now().difference(entry.resolvedAt) > _cacheValidationDuration) {
    _selectedAudioStreams.remove(key);
    return null;
  }

  return entry.stream;
}

void _cacheSelectedAudioStream(String songId, AudioOnlyStreamInfo stream) {
  if (_selectedAudioStreams.length >= _maxSelectedAudioStreams) {
    _selectedAudioStreams.remove(_selectedAudioStreams.keys.first);
  }

  _selectedAudioStreams[_selectedAudioStreamKey(songId)] = (
    stream: stream,
    resolvedAt: DateTime.now(),
  );
}

/// Drops both cached forms of a song's stream, so the next request resolves
/// it again. Used when a cached URL turns out to be dead.
Future<void> invalidateSongStreamCache(String songId) async {
  _selectedAudioStreams.remove(_selectedAudioStreamKey(songId));
  await deleteData('cache', 'song_${songId}_${audioQualitySetting.value}_url');
}

/// Fetches the best available audio stream for a song.
Future<AudioOnlyStreamInfo?> fetchBestAudioStream(String? songId) async {
  try {
    if (songId == null || songId.isEmpty || isLocalTrackId(songId)) {
      logger.log('fetchBestAudioStream: songId is null or empty');
      return null;
    }

    final cachedStream = _getSelectedAudioStream(songId);
    if (cachedStream != null) return cachedStream;

    final manifest = await _fetchStreamManifest(songId);
    final audioStream = manifest?.audioOnly;
    if (audioStream == null || audioStream.isEmpty) {
      logger.log('fetchBestAudioStream: no audio streams for $songId');
      return null;
    }

    final selectedStream = selectAudioOnlyStreamForQuality(audioStream);
    if (selectedStream == null) {
      logger.log(
        'fetchBestAudioStream: no compatible audio streams for $songId',
      );
      return null;
    }

    _cacheSelectedAudioStream(songId, selectedStream);
    return selectedStream;
  } on TimeoutException catch (_) {
    logger.log('fetchBestAudioStream request timed out for $songId');
    return null;
  } catch (e, stackTrace) {
    logger.log(
      'Error while fetching best audio stream',
      error: e,
      stackTrace: stackTrace,
    );
    return null;
  }
}

/// Resolves a playable stream URL for a song (cached when possible).
Future<String?> fetchSongStreamUrl(String songId, bool isLive) async {
  try {
    if (songId.isEmpty || isLocalTrackId(songId)) {
      logger.log('fetchSongStreamUrl: songId is empty');
      return null;
    }
    if (isLive) {
      final streamInfo = await ytClient.videos.streamsClient
          .getHttpLiveStreamUrl(VideoId(songId));
      return streamInfo;
    }

    const _cacheDuration = Duration(hours: 3);
    final cacheKey = 'song_${songId}_${audioQualitySetting.value}_url';

    // Try to get from cache
    final cachedUrl = await _getCachedSongUrl(songId, cacheKey, _cacheDuration);
    if (cachedUrl != null) {
      return cachedUrl;
    }

    // Get fresh URL, reusing the stream already resolved for this song.
    final selectedStream = await fetchBestAudioStream(songId);
    if (selectedStream == null) {
      logger.log('fetchSongStreamUrl: no audio streams for $songId');
      return null;
    }

    final url = selectedStream.url.toString();

    unawaited(addOrUpdateData<String>('cache', cacheKey, url));

    return url;
  } on TimeoutException catch (_) {
    logger.log('fetchSongStreamUrl request timed out for $songId');
    return null;
  } catch (e, stackTrace) {
    logger.log(
      'Error in fetchSongStreamUrl for $songId:',
      error: e,
      stackTrace: stackTrace,
    );
    return null;
  }
}

Future<Map<String, dynamic>> getSongDetails(
  int songIndex,
  String songId,
) async {
  if (isNonYoutubeId(songId)) {
    final local = getOfflineSongByYtid(songId);
    if (local.isEmpty)
      throw StateError('Local file unavailable; import its folder again');
    return Map<String, dynamic>.from(local);
  }
  try {
    final song = await ytClient.videos.get(songId);
    return returnSongLayout(songIndex, song);
  } catch (e, stackTrace) {
    logger.log(
      'Error while getting song details',
      error: e,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}

Lyrics? _lastLyricsResult;
int _lyricsRequestCounter = 0;

/// Plain-text version of [result] as shown for unsynced lyrics.
String formatPlainLyrics(Lyrics result) {
  return '${result.text}\n\n© ${result.source}'
      .replaceAll(RegExp(r'\n{4}'), '\n\n')
      .replaceAll(RegExp(r'\n{2}'), '\n');
}

/// Fetches lyrics for a song, keeping timestamps when the provider has them.
Future<Lyrics?> getSongLyricsResult(
  String? artist,
  String title, {
  Duration? duration,
  String? album,
}) async {
  if (artist == null) return null;
  final key = '$artist - $title';
  if (lastFetchedLyrics == key) return _lastLyricsResult;

  lyrics.value = null;
  final requestId = ++_lyricsRequestCounter;
  final result = await LyricsManager().fetchLyricsResult(
    TrackInfo(title: title, artist: artist, album: album, duration: duration),
  );
  if (result == null) return null;

  // Ignore the response if the user already moved on to another song.
  if (requestId == _lyricsRequestCounter) {
    _lastLyricsResult = result;
    lyrics.value = formatPlainLyrics(result);
    lastFetchedLyrics = key;
  }
  return result;
}

final Map<String, Future<bool>> _downloadJobs = {};
Future<bool> makeSongOffline(dynamic song) {
  if (song is! Map) return Future.value(false);
  final id = song['ytid']?.toString();
  if (id == null || id.isEmpty) return Future.value(false);
  return _downloadJobs.putIfAbsent(
    id,
    () => _downloadSong(song).whenComplete(() {
      _downloadJobs.remove(id);
    }),
  );
}

Future<bool> _downloadSong(Map song) async {
  File? staging;
  try {
    final id = song['ytid'].toString();
    final existing = getOfflineSongByYtid(id);
    if (existing.isNotEmpty &&
        await MusicStorageService.playbackPath(existing) != null)
      return true;
    if (isLocalTrack(song))
      return await MusicStorageService.playbackPath(song) != null;
    final destination = MusicStorageService.downloadFolder;
    final lossless = isExtensionTrack(song);
    final manifest = lossless ? null : await fetchBestAudioStream(id);
    if (!lossless && manifest == null) return false;
    final container = lossless ? 'flac' : manifest!.container.name;
    if (!{'mp4', 'webm', '3gpp', 'flac'}.contains(container)) return false;
    final extension = container == 'mp4' ? 'm4a' : container;
    final filename = safeAudioFilename(
      '${song['artist'] ?? ''} - ${song['title'] ?? 'Track'}',
      id,
      extension,
    );
    await FilePaths.ensureDirectoriesExist();
    final storageId = id.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
    staging = File(
      '$applicationDirPath/${FilePaths.tracksDir}/$storageId.partial',
    );
    if (lossless) {
      await FlacExtensionService.instance.download(song, staging);
    } else {
      final sink = staging.openWrite();
      try {
        await sink.addStream(ytClient.videos.streamsClient.get(manifest!));
        await sink.flush();
      } finally {
        await sink.close();
      }
    }
    if (await staging.length() == 0)
      throw const FormatException('Empty audio stream');
    final offline = Map<String, dynamic>.from(song)
      ..remove('audioUri')
      ..remove('audioPath')
      ..remove('sourceUri');
    if (destination == null) {
      final completed = await staging.rename(
        '$applicationDirPath/${FilePaths.tracksDir}/$storageId.$extension',
      );
      offline['audioPath'] = completed.path;
      offline['fileOwnership'] = 'app-download';
    } else {
      offline['audioUri'] = await MusicStorageService.publish(
        staging,
        destination,
        filename,
        container == 'flac'
            ? 'audio/flac'
            : container == 'webm'
            ? 'audio/webm'
            : container == '3gpp'
            ? 'audio/3gpp'
            : 'audio/mp4',
      );
      offline.remove('audioPath');
      offline['fileOwnership'] = 'user-download';
    }
    if (manifest != null)
      offline['audioBitrateKbps'] = manifest.bitrate.kiloBitsPerSecond.round();
    offline['audioCodec'] = lossless ? 'flac' : manifest!.audioCodec;
    offline['dateAdded'] = DateTime.now().millisecondsSinceEpoch;
    final artworkPath = FilePaths.getArtworkPath(id);
    try {
      final image = offline['highResImage']?.toString();
      if (image != null && image.isNotEmpty) {
        final artwork = await _downloadAndSaveArtworkFile(image, artworkPath);
        if (artwork != null) offline['artworkPath'] = artwork.path;
      }
    } catch (_) {
      /* Artwork is optional. */
    }
    await MusicStorageService.mutateOfflineSongs(
      (current) => current
        ..removeWhere((s) => s['ytid'] == id)
        ..add(offline),
      onSaved: (next) => userOfflineSongs.value = next,
    );
    unawaited(cacheSponsorBlockSegments(id));
    return true;
  } catch (e, st) {
    logger.log(
      'Download failed (check destination access)',
      error: e,
      stackTrace: st,
    );
    return false;
  } finally {
    if (staging != null && await staging.exists()) await staging.delete();
  }
}

Future<void> _deleteFileIfExists(File file, String errorDescription) async {
  try {
    if (await file.exists()) {
      await file.delete(recursive: true);
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error deleting $errorDescription',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

Future<bool> removeSongFromOffline(dynamic songId) async {
  try {
    final offline = getOfflineSongByYtid(songId);
    // Imported originals and user-folder exports are never deleted here.
    if (!isLocalTrackId(songId)) {
      final path =
          offline['audioPath']?.toString() ?? FilePaths.getAudioPath(songId);
      final privateRoot = Directory(
        '$applicationDirPath/${FilePaths.tracksDir}',
      ).absolute.path;
      if (File(path).absolute.uri
          .normalizePath()
          .toFilePath()
          .startsWith('$privateRoot${Platform.pathSeparator}')) {
        await _deleteFileIfExists(File(path), 'private audio file');
      }
      await _deleteFileIfExists(
        File(FilePaths.getArtworkPath(songId)),
        'artwork',
      );
    }

    try {
      await MusicStorageService.mutateOfflineSongs(
        (current) => current..removeWhere((s) => s['ytid'] == songId),
        onSaved: (next) => userOfflineSongs.value = next,
      );
    } catch (e, st) {
      logger.log(
        'Error updating offline songs registry after removal',
        error: e,
        stackTrace: st,
      );
    }

    return true;
  } catch (e, stackTrace) {
    logger.log(
      'Error removing song from offline storage',
      error: e,
      stackTrace: stackTrace,
    );
    return false;
  }
}

const _sponsorCallSpacing = Duration(seconds: 1);
Future<void> _sponsorSerialChain = Future.value();

/// Runs SponsorBlock lookups one at a time, spaced out, so that a playlist
/// download finishing several songs at once does not fire them all together.
Future<T> _sponsorSerialCall<T>(Future<T> Function() action) {
  final result = _sponsorSerialChain.then((_) => action());
  _sponsorSerialChain = result
      .then((_) {}, onError: (_) {})
      .then((_) => Future<void>.delayed(_sponsorCallSpacing));
  return result;
}

/// Stores the SponsorBlock segments of a downloaded song next to the download
/// itself, so they last exactly as long as it does: they are not backed up,
/// they never expire, and removing the song removes them.
///
/// Looked up once per song: a stored result — including a confirmed empty one —
/// is never fetched again.
Future<void> cacheSponsorBlockSegments(String ytid) async {
  if (isNonYoutubeId(ytid)) return;
  try {
    if (getOfflineSongByYtid(ytid)['sponsorSegments'] != null) return;

    // Two attempts, spaced out by the queue above; a failure stores nothing so
    // it is not mistaken for a confirmed "no segments", and is looked up again
    // the next time the song plays.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final segments = await _sponsorSerialCall(
          () => _fetchSkipSegments(ytid),
        );
        await _storeSponsorBlockSegments(ytid, segments);
        return;
      } catch (_) {
        continue;
      }
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error caching sponsor block for $ytid',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

Future<void> _storeSponsorBlockSegments(
  String ytid,
  List<Map<String, int>> segments,
) async {
  await MusicStorageService.mutateOfflineSongs((current) {
    final index = current.indexWhere((s) => s['ytid'] == ytid);
    if (index != -1)
      current[index] = {
        ...Map<String, dynamic>.from(current[index] as Map),
        'sponsorSegments': segments,
      };
    return current;
  }, onSaved: (next) => userOfflineSongs.value = next);
}

/// The stored segments of a downloaded song, or null when it has none stored
/// yet. An empty list means the song was looked up and has no segments.
List<Map<String, int>>? getCachedSponsorBlockSegments(String ytid) {
  final stored = getOfflineSongByYtid(ytid)['sponsorSegments'];
  if (stored is! List) return null;
  return [for (final segment in stored) Map<String, int>.from(segment as Map)];
}

Future<File?> _downloadAndSaveArtworkFile(String url, String filePath) async {
  try {
    final response = await ProxyManager().getProxiedResponse(Uri.parse(url));

    if (response.statusCode == 200) {
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);

      // Validate that the file was actually written
      if (await file.exists() && await file.length() > 0) {
        return file;
      } else {
        logger.log('Artwork file was not written properly: $filePath');
        return null;
      }
    } else {
      logger.log(
        'Failed to download file. Status code: ${response.statusCode}',
      );
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error downloading and saving file',
      error: e,
      stackTrace: stackTrace,
    );
  }

  return null;
}

const recentlyPlayedSongsLimit = 100;

/// Updates the recently played list and listening count for [songId].
///
/// When [songFallback] is provided, its metadata is used to seed the history
/// entry if the song has never been played before. This avoids a network
/// request when registering offline songs whose metadata is already available
/// locally (e.g. from [userOfflineSongs]).
Future<void> updateRecentlyPlayed(dynamic songId, {Map? songFallback}) async {
  try {
    final now = DateTime.now();

    if (userRecentlyPlayed.value.isNotEmpty &&
        userRecentlyPlayed.value[0]['ytid'] == songId) {
      final updatedList = List.from(userRecentlyPlayed.value);
      final existing = Map.from(updatedList[0] as Map);
      existing['listeningCount'] = (existing['listeningCount'] ?? 0) + 1;
      existing['lastPlayed'] = now;
      updatedList[0] = existing;
      userRecentlyPlayed.value = updatedList;
      unawaited(
        addOrUpdateData<List>(
          'user',
          'recentlyPlayedSongs',
          userRecentlyPlayed.value,
        ),
      );
      return;
    }

    final existingIndex = userRecentlyPlayed.value.indexWhere(
      (song) => song['ytid'] == songId,
    );

    final updatedList = List.from(userRecentlyPlayed.value);

    if (existingIndex == -1 && updatedList.length >= recentlyPlayedSongsLimit) {
      updatedList.removeLast();
    }

    if (existingIndex != -1) {
      final song = Map.from(updatedList.removeAt(existingIndex) as Map);
      song['listeningCount'] = (song['listeningCount'] ?? 0) + 1;
      song['lastPlayed'] = now;
      updatedList.insert(0, song);
    } else {
      final dynamic fetchedSongDetails = songFallback != null
          ? Map<String, dynamic>.from(songFallback)
          : await getSongDetails(0, songId);

      if (fetchedSongDetails is! Map) {
        logger.log('Failed to update recently played: invalid song details');
        return;
      }

      final newSongDetails = Map<String, dynamic>.from(fetchedSongDetails);
      newSongDetails['ytid'] ??= songId;
      newSongDetails['listeningCount'] = 1;
      newSongDetails['lastPlayed'] = now;
      updatedList.insert(0, newSongDetails);
    }

    userRecentlyPlayed.value = updatedList;
    unawaited(
      addOrUpdateData<List>(
        'user',
        'recentlyPlayedSongs',
        userRecentlyPlayed.value,
      ),
    );
  } catch (e, stackTrace) {
    logger.log(
      'Error updating recently played',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

Future<void> removeFromRecentlyPlayed(dynamic songId) async {
  if (userRecentlyPlayed.value.any((song) => song['ytid'] == songId)) {
    userRecentlyPlayed.value = List.from(userRecentlyPlayed.value)
      ..removeWhere((song) => song['ytid'] == songId);
    unawaited(
      addOrUpdateData<List>(
        'user',
        'recentlyPlayedSongs',
        userRecentlyPlayed.value,
      ),
    );
  }
}
