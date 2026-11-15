import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/services/data_manager.dart';
import 'package:yazhal/services/listening_stats_service.dart';
import 'package:yazhal/services/stats_backup_service.dart';
import 'package:yazhal/utilities/listening_stats_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final month = listeningStatsMonthKey(DateTime.now());
  Map<String, dynamic> stats() => {
    'schemaVersion': 2,
    'year': DateTime.now().year,
    'currentMonthKey': month,
    'currentMonth': {
      'totalSeconds': 120,
      'songs': {
        'local:abcd': {
          'ytid': 'local:abcd',
          'title': 'Song',
          'artist': 'Artist',
          'seconds': 120,
          'playCount': 2,
          'listeningCount': 2,
          'lastPlayed': DateTime.now().toIso8601String(),
          'filePath': '/private/music.flac',
          'token': 'secret',
        },
      },
    },
    'history': <String, dynamic>{},
    'secret': 'excluded',
  };
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('yazhal_stats');
    Hive.init(directory.path);
    for (final name in ['user', 'settings', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  setUp(() async {
    listeningStatsService.reload();
    await addOrUpdateData('user', ListeningStatsService.storageKey, stats());
    await Hive.box('userNoBackup').put('offlinePlaybackHistory', [
      {
        'ytid': 'local:abcd',
        'title': 'Song',
        'plays': 2,
        'lastPlayed': 1000,
        'filePath': '/private/music.flac',
        'credential': 'secret',
      },
    ]);
    listeningStatsService.reload();
  });
  test(
    'portable export round trips totals, counts, dates and offline history',
    () async {
      final bytes = await StatsBackupService.export();
      final decoded = StatsBackupService.decode(bytes);
      final current = decoded['listeningStats']['currentMonth'];
      expect(current['totalSeconds'], 120);
      expect(current['songs']['local:abcd']['playCount'], 2);
      expect(current['songs']['local:abcd']['lastPlayed'], isA<String>());
      expect(decoded['offlinePlaybackHistory'][0]['plays'], 2);
      expect(decoded['offlinePlaybackHistory'][0]['lastPlayed'], 1000);
      expect(utf8.decode(bytes), isNot(contains('secret')));
      expect(utf8.decode(bytes), isNot(contains('/private/')));
    },
  );
  test(
    'restore is idempotent and does not replace music, settings or secrets',
    () async {
      final decoded = StatsBackupService.decode(
        await StatsBackupService.export(),
      );
      await addOrUpdateData('user', 'likedSongs', ['keep']);
      await Hive.box('settings').put('extensionPassword', 'keep-secret');
      await StatsBackupService.restore(decoded);
      await StatsBackupService.restore(decoded);
      expect(
        Hive.box(
          'user',
        ).get(ListeningStatsService.storageKey)['currentMonth']['totalSeconds'],
        120,
      );
      expect(Hive.box('userNoBackup').get('offlinePlaybackHistory').length, 1);
      expect(Hive.box('user').get('likedSongs'), ['keep']);
      expect(Hive.box('settings').get('extensionPassword'), 'keep-secret');
    },
  );
  test('rejects unsupported or malformed files before changing storage', () {
    for (final value in [
      <String, dynamic>{},
      {'format': 'yazhal-stats-backup', 'version': 99},
      {
        'format': 'yazhal-stats-backup',
        'version': 1,
        'listeningStats': {},
        'offlinePlaybackHistory': [],
      },
    ]) {
      expect(
        () => StatsBackupService.decode(utf8.encode(jsonEncode(value))),
        throwsFormatException,
      );
    }
    expect(
      () => StatsBackupService.decode(utf8.encode('{broken')),
      throwsFormatException,
    );
    expect(
      Hive.box(
        'user',
      ).get(ListeningStatsService.storageKey)['currentMonth']['totalSeconds'],
      120,
    );
  });
  test(
    'playlist popularity exports safely and restores without duplication',
    () async {
      await Hive.box('user').put('playlistPlayCounts', {
        'local:mix': 5,
        '/private/path': 9,
        'bad': -1,
      });
      final bytes = await StatsBackupService.export();
      final decoded = StatsBackupService.decode(bytes);
      expect(decoded['playlistPlayCounts'], {'local:mix': 5});
      expect(utf8.decode(bytes), isNot(contains('/private/')));
      await Hive.box('user').put('playlistPlayCounts', <String, int>{});
      await StatsBackupService.restore(decoded);
      await StatsBackupService.restore(decoded);
      expect(Hive.box('user').get('playlistPlayCounts'), {'local:mix': 5});
    },
  );
  test('rejects oversized input', () {
    expect(
      () => StatsBackupService.decode(
        List.filled(StatsBackupService.maxBytes + 1, 0),
      ),
      throwsFormatException,
    );
  });
}
