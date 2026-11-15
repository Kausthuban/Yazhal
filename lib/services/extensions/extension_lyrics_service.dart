import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/services/extensions/native_extension_service.dart';
import 'package:yazhal/services/lyrics/lrc_parser.dart';
import 'package:yazhal/services/lyrics/lyrics_models.dart';

class ExtensionLyricsService {
  static Future<Lyrics?> fetch(TrackInfo track) async {
    if (!Hive.isBoxOpen('settings')) return null;
    final selected = Hive.box('settings')
        .get('lyricsExtension', defaultValue: 'automatic')
        .toString();
    if (selected == 'builtin') return null;
    final providers = NativeExtensionService.enabled.where((p) {
      final types = (p['manifest'] as Map?)?['type'];
      return types is List &&
          types.contains('lyrics_provider') &&
          (selected == 'automatic' || selected == p['id']);
    });
    for (final provider in providers) {
      try {
        final raw = await NativeExtensionService.instance.call(
          provider['id'].toString(),
          'fetchLyrics',
          [
            track.title,
            track.artist,
            track.album ?? '',
            track.duration?.inSeconds ?? 0,
          ],
        );
        if (raw == null) continue;
        final result = normalize(
          raw,
          '${provider['name']} · extension ${provider['version']}',
        );
        if (!result.isEmpty) return result;
      } catch (_) {
        /* Optional source may be unavailable or account gated. Built-ins remain usable. */
      }
    }
    return null;
  }

  static Lyrics normalize(dynamic raw, String source) {
    String? plain, lrc;
    List<LyricLine>? lines;
    if (raw is String) {
      if (RegExp(r'\[\d+:\d+').hasMatch(raw)) {
        lrc = raw;
      } else {
        plain = raw;
      }
    } else if (raw is Map) {
      plain =
          (raw['plainLyrics'] ??
                  raw['plain_lyrics'] ??
                  raw['lyrics'] ??
                  raw['text'])
              ?.toString();
      lrc = (raw['syncedLyrics'] ?? raw['synced_lyrics'] ?? raw['lrc'])
          ?.toString();
      final rawLines = (raw['lines'] as List? ?? []).whereType<Map>().toList();
      if (raw['syncType'] != 'UNSYNCED' && rawLines.isNotEmpty) {
        lines = <LyricLine>[];
        for (final line in rawLines) {
          final ms = num.tryParse(line['startTimeMs']?.toString() ?? '');
          final text = (line['words'] ?? line['text'] ?? '').toString();
          if (ms != null &&
              ms >= 0 &&
              ms < 24 * 60 * 60 * 1000 &&
              text.trim().isNotEmpty)
            lines.add(LyricLine(Duration(milliseconds: ms.round()), text));
        }
        lines.sort((a, b) => a.start.compareTo(b.start));
      } else if ((plain == null || plain.isEmpty) && rawLines.isNotEmpty) {
        plain = rawLines.map((l) => l['words'] ?? l['text'] ?? '').join('\n');
      }
      if (raw['instrumental'] == true && (plain == null || plain.isEmpty))
        plain = 'Instrumental';
    }
    return Lyrics(
      source: source,
      plain: plain,
      synced: lines?.isNotEmpty == true
          ? lines
          : lrc == null
          ? null
          : parseLrc(lrc),
    );
  }
}
