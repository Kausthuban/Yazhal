import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/main.dart' show logger;
import 'package:yazhal/services/audio_service.dart';
import 'package:yazhal/services/settings_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late YazhalAudioHandler handler;
  late int logCount;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('yazhal_navigation');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    playNextSongAutomatically.value = false;
    offlineMode.value = false;
    repeatNotifier.value = AudioServiceRepeatMode.none;
    logCount = logger.getLogCount();
    handler = YazhalAudioHandler();
    await Future<void>.delayed(const Duration(milliseconds: 250));
  });

  tearDown(() async {
    await handler.audioPlayer.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(logger.getLogCount(), logCount);
    debugDefaultTargetPlatformOverride = null;
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Map<String, dynamic> song(String id) => {
    'ytid': id,
    'title': id,
    'artist': 'Artist',
    'highResImage': '',
    'lowResImage': '',
    'isLive': false,
  };

  test('empty queue cannot navigate even with repeat or auto picker', () {
    repeatNotifier.value = AudioServiceRepeatMode.all;
    playNextSongAutomatically.value = true;
    expect(handler.canSkipToNext, false);
    expect(handler.hasPrevious, false);
  });

  test(
    'single track has no next or previous without queue repetition',
    () async {
      await handler.addPlaylistToQueue([song('first')]);
      expect(handler.canSkipToNext, false);
      expect(handler.hasPrevious, false);
      repeatNotifier.value = AudioServiceRepeatMode.one;
      expect(handler.canSkipToNext, false);
      repeatNotifier.value = AudioServiceRepeatMode.all;
      expect(handler.canSkipToNext, true);
      expect(handler.hasPrevious, false);
    },
  );

  test('queue edits enable and remove next without playback', () async {
    await handler.addPlaylistToQueue([song('first')]);
    await handler.addPlaylistToQueue([song('second')]);
    expect(handler.canSkipToNext, true);
    handler.clearQueue();
    expect(handler.canSkipToNext, false);
    expect(handler.hasPrevious, false);
  });

  test(
    'bulk queue append preserves existing order and playback state',
    () async {
      await handler.addPlaylistToQueue([song('first')]);
      final current = handler.mediaItem.value;
      final position = handler.audioPlayer.position;
      await handler.addPlaylistToQueue([
        song('local:imported'),
        song('third'),
        song('third'),
      ]);
      expect(handler.queue.value.map((item) => item.extras?['ytid']), [
        'first',
        'local:imported',
        'third',
        'third',
      ]);
      expect(handler.mediaItem.value?.id, current?.id);
      expect(handler.mediaItem.value?.title, current?.title);
      expect(handler.audioPlayer.position, position);
      expect(handler.audioPlayer.playing, isFalse);
    },
  );

  test('paused auto picker cannot advance an exhausted queue', () async {
    await handler.addPlaylistToQueue([song('first')]);
    playNextSongAutomatically.value = true;
    expect(handler.canSkipToNext, false);
    offlineMode.value = true;
    expect(handler.canSkipToNext, false);
    await handler.addPlaylistToQueue([song('second')]);
    expect(handler.canSkipToNext, true);
  });
}
