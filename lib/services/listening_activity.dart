import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

class ListeningActivity {
  static final changes = ValueNotifier<int>(0);
  static Future<void> _writes = Future.value();
  static Map get playlistCounts =>
      Hive.box('user')
              .get('playlistPlayCounts', defaultValue: <String, dynamic>{})
          as Map;
  static Future<void> record(Map song) {
    final id = song['_originPlaylistId']?.toString() ?? '';
    if (id.isEmpty) return Future.value();
    final operation = _writes.then((_) async {
      final counts = Map<String, dynamic>.from(playlistCounts);
      counts[id] = ((counts[id] as num?)?.toInt() ?? 0) + 1;
      await Hive.box('user').put('playlistPlayCounts', counts);
      changes.value++;
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  static List<Map> frequentPlaylists(Iterable<Map> playlists, Map counts) {
    final result =
        playlists.where((p) => ((counts[p['ytid']] as num?) ?? 0) > 0).toList()
          ..sort(
            (a, b) => ((counts[b['ytid']] as num?) ?? 0).compareTo(
              (counts[a['ytid']] as num?) ?? 0,
            ),
          );
    return result.take(4).toList();
  }

  static List<Map> frequentSongs(Iterable<Map> songs) {
    final result = songs.toList()
      ..sort(
        (a, b) => ((b['listeningCount'] ?? b['playCount'] ?? 0) as num)
            .compareTo((a['listeningCount'] ?? a['playCount'] ?? 0) as num),
      );
    return result.take(6).toList();
  }
}
