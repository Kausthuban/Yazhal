import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/services/data_manager.dart';
import 'package:yazhal/services/listening_activity.dart';
import 'package:yazhal/services/listening_stats_service.dart';
import 'package:yazhal/services/offline_taste_service.dart';
import 'package:yazhal/utilities/listening_stats_utils.dart';

/// A portable data file, never a login/session/settings or executable backup.
class StatsBackupService {
  static Map<String, int> cleanPlaylistCounts(dynamic value) {
    if (value is! Map) return {};
    return {
      for (final entry in value.entries.take(1000))
        if (entry.key is String &&
            RegExp(r'^[a-zA-Z0-9_.:-]{1,256}$').hasMatch(entry.key as String) &&
            entry.value is num &&
            (entry.value as num).isFinite &&
            (entry.value as num) >= 0)
          entry.key as String: (entry.value as num).toInt().clamp(
            0,
            1000000000,
          ),
    };
  }

  static const maxBytes = 5 * 1024 * 1024;
  static Map<String, dynamic> sanitize(dynamic raw) {
    final normalized = normalizeListeningStats(raw, DateTime.now());
    Map month(dynamic value) {
      final m = value as Map? ?? {};
      final songs = m['songs'] as Map? ?? {};
      return {
        'totalSeconds': m['totalSeconds'] ?? 0,
        'songs': {
          for (final entry in songs.entries.take(1000))
            entry.key.toString(): cleanSong(entry.value),
        },
      };
    }

    return {
      'schemaVersion': normalized['schemaVersion'],
      'year': normalized['year'],
      'currentMonthKey': normalized['currentMonthKey'],
      'currentMonth': month(normalized['currentMonth']),
      'history': {
        for (final entry in (normalized['history'] as Map).entries)
          entry.key.toString(): month(entry.value),
      },
    };
  }

  static Map<String, dynamic> cleanSong(dynamic value) {
    final m = value as Map? ?? {};
    return {
      for (final key in ['ytid', 'title', 'artist', 'album'])
        if (m[key] is String)
          key: (m[key] as String).substring(
            0,
            (m[key] as String).length.clamp(0, 1000),
          ),
      if (m['lastPlayed'] is String &&
          DateTime.tryParse(m['lastPlayed'] as String) != null)
        'lastPlayed': m['lastPlayed'],
      for (final key in [
        'duration',
        'seconds',
        'playCount',
        'listeningCount',
        'plays',
        'lastPlayed',
      ])
        if (m[key] is num && (m[key] as num).isFinite && (m[key] as num) >= 0)
          key: m[key],
    };
  }

  static Future<Uint8List> export() async {
    listeningStatsService.recordListeningSessionProgress();
    await listeningStatsService.flush();
    final record = {
      'format': 'yazhal-stats-backup',
      'version': 1,
      'playlistPlayCounts': cleanPlaylistCounts(
        Hive.box('user').get('playlistPlayCounts'),
      ),
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'listeningStats': sanitize(
        Hive.box('user').get(ListeningStatsService.storageKey),
      ),
      'offlinePlaybackHistory': OfflineTasteService.history
          .take(1000)
          .map(cleanSong)
          .toList(),
    };
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(record)),
    );
    if (bytes.length > maxBytes)
      throw const FormatException('Statistics exceed the 5 MiB backup limit');
    return bytes;
  }

  static Map<String, dynamic> decode(List<int> bytes) {
    if (bytes.length > maxBytes)
      throw const FormatException('Backup exceeds 5 MiB');
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map ||
        raw['format'] != 'yazhal-stats-backup' ||
        raw['version'] != 1 ||
        raw['listeningStats'] is! Map ||
        raw['offlinePlaybackHistory'] is! List)
      throw const FormatException('Not a supported Yazhal statistics backup');
    final stats = raw['listeningStats'] as Map;
    if (stats['currentMonth'] is! Map || stats['history'] is! Map)
      throw const FormatException('Invalid listening statistics');
    return {
      'listeningStats': sanitize(stats),
      'playlistPlayCounts': cleanPlaylistCounts(raw['playlistPlayCounts']),
      'offlinePlaybackHistory': (raw['offlinePlaybackHistory'] as List)
          .whereType<Map>()
          .take(1000)
          .map(cleanSong)
          .toList(),
    };
  }

  static Future<void> restore(Map<String, dynamic> data) async {
    listeningStatsService.recordListeningSessionProgress();
    await listeningStatsService.flush();
    final before = Hive.box('user').get(ListeningStatsService.storageKey);
    final oldCounts = Hive.box('user').get('playlistPlayCounts');
    final history = Hive.box('userNoBackup')
        .get('offlinePlaybackHistory', defaultValue: []);
    try {
      await addOrUpdateData(
        'user',
        ListeningStatsService.storageKey,
        data['listeningStats'],
      );
      await Hive.box('userNoBackup')
          .put('offlinePlaybackHistory', data['offlinePlaybackHistory']);
      await addOrUpdateData(
        'user',
        'playlistPlayCounts',
        data['playlistPlayCounts'] ?? <String, int>{},
      );
    } catch (_) {
      if (before == null) {
        await deleteData('user', ListeningStatsService.storageKey);
      } else {
        await addOrUpdateData('user', ListeningStatsService.storageKey, before);
      }
      await Hive.box('userNoBackup').put('offlinePlaybackHistory', history);
      if (oldCounts == null) {
        await deleteData('user', 'playlistPlayCounts');
      } else {
        await addOrUpdateData('user', 'playlistPlayCounts', oldCounts);
      }
      rethrow;
    } finally {
      listeningStatsService.reload();
      OfflineTasteService.changes.value++;
      ListeningActivity.changes.value++;
    }
  }
}
