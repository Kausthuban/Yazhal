import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/services/lyrics/lyrics_models.dart';

class OfflineLyricsStore {
  static String key(TrackInfo track) =>
      'savedLyrics:${sha256.convert(utf8.encode('${track.artist.trim().toLowerCase()}|${track.title.trim().toLowerCase()}|${track.album?.trim().toLowerCase() ?? ''}'))}';
  static Lyrics? read(TrackInfo track) {
    if (!Hive.isBoxOpen('cache')) return null;
    try {
      final raw = Hive.box('cache').get(key(track));
      if (raw is! Map) return null;
      final lines = (raw['lines'] as List? ?? [])
          .whereType<Map>()
          .map(
            (l) => LyricLine(
              Duration(milliseconds: (l['ms'] as num).round()),
              l['text'].toString(),
            ),
          )
          .toList();
      return Lyrics(
        source: raw['source'].toString(),
        plain: raw['plain']?.toString(),
        synced: lines.isEmpty ? null : lines,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(TrackInfo track, Lyrics lyrics) async {
    if (!Hive.isBoxOpen('cache') || lyrics.isEmpty) return;
    final raw = {
      'source': lyrics.source,
      'plain': lyrics.plain,
      'lines': [
        for (final line in lyrics.synced ?? <LyricLine>[])
          {'ms': line.start.inMilliseconds, 'text': line.text},
      ],
    };
    if (utf8.encode(jsonEncode(raw)).length > 256 * 1024) return;
    final box = Hive.box('cache');
    await box.put(key(track), raw);
    final keys = box.keys
        .whereType<String>()
        .where((k) => k.startsWith('savedLyrics:'))
        .toList();
    if (keys.length > 64) await box.deleteAll(keys.take(keys.length - 64));
  }
}
