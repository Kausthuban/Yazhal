import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

/// A local-only preference profile. No paths, audio, or full history are sent.
class OfflineTasteProfile {
  OfflineTasteProfile(Iterable<Map> library, Iterable<Map> history) {
    for (final song in library) {
      _add(song, 1);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final song in history) {
      final age = max(0, now - ((song['lastPlayed'] as num?)?.toInt() ?? now));
      final count = max(1, (song['plays'] as num?)?.toInt() ?? 1);
      _add(
        song,
        (1 + log(count + 1)) /
            (1 + age / const Duration(days: 30).inMilliseconds),
      );
      plays[song['ytid'].toString()] = count;
    }
  }
  final artists = <String, double>{};
  final albums = <String, double>{};
  final plays = <String, int>{};
  final titles = <String>{};
  static String normalize(Object? value) =>
      (value ?? '').toString().trim().toLowerCase();
  void _add(Map song, double weight) {
    final title = (song['title'] ?? '').toString().trim();
    if (title.isNotEmpty && titles.length < 1000) titles.add(title);
    final artist = normalize(song['artist']);
    final album = normalize(song['album']);
    if (artist.isNotEmpty)
      artists.update(artist, (v) => v + weight, ifAbsent: () => weight);
    if (album.isNotEmpty)
      albums.update(album, (v) => v + weight / 2, ifAbsent: () => weight / 2);
  }

  double affinity(Map song) =>
      (artists[normalize(song['artist'])] ?? 0) +
      (albums[normalize(song['album'])] ?? 0);
  List<Map> rank(Iterable<Map> songs, {bool local = false}) {
    // Start with a shuffle to give ties a fresh order on refresh.
    final list = songs.toList()..shuffle();
    double score(Map s) =>
        affinity(s) /
        (local ? 1 + log(1 + (plays[s['ytid'].toString()] ?? 0)) : 1);
    list.sort((a, b) => score(b).compareTo(score(a)));
    return list;
  }

  List<String> get discoveryQueries {
    final entries = artists.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final queries = entries.take(3).map((e) => '${e.key} music').toList();
    if (queries.isEmpty)
      queries.addAll(
        (titles.toList()..shuffle()).take(3).map((t) => '$t music'),
      );
    return queries..shuffle();
  }
}

class OfflineTasteService {
  static final changes = ValueNotifier<int>(0);
  static Future<void> _writes = Future.value();
  static bool get enabled =>
      Hive.box('settings').get('offlineTasteEnabled', defaultValue: true) ==
      true;
  static List<Map> get history => (Hive.box('userNoBackup').get(
    'offlinePlaybackHistory',
    defaultValue: <dynamic>[],
  ) as List).whereType<Map>().toList();
  static OfflineTasteProfile profile(Iterable<Map> library) =>
      OfflineTasteProfile(library, history);

  /// Invoked once after an offline source actually starts, never on preparation.
  static Future<void> record(Map song) {
    final snapshot = <String, dynamic>{
      for (final key in ['ytid', 'title', 'artist', 'album', 'duration'])
        if (song[key] != null) key: song[key],
    };
    final operation = _writes.then((_) async {
      if (!enabled) return;
      final list = history;
      final previous = list.where((s) => s['ytid'] == song['ytid']).firstOrNull;
      list
        ..removeWhere((s) => s['ytid'] == song['ytid'])
        ..insert(0, {
          ...snapshot,
          'plays': ((previous?['plays'] as num?)?.toInt() ?? 0) + 1,
          'lastPlayed': DateTime.now().millisecondsSinceEpoch,
        });
      await Hive.box('userNoBackup')
          .put('offlinePlaybackHistory', list.take(1000).toList());
      changes.value++;
    });
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  static Future<void> clear() {
    final operation = _writes.then((_) async {
      await Hive.box('userNoBackup').delete('offlinePlaybackHistory');
      changes.value++;
    });
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }
}
