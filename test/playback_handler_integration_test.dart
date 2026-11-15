import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:yazhal/services/audio_service.dart';
import 'package:yazhal/services/common_services.dart';
import 'package:yazhal/services/extensions/extension_package.dart';
import 'package:yazhal/services/extensions/native_extension_service.dart';
import 'package:yazhal/services/playback_cache.dart';
import 'package:yazhal/services/settings_manager.dart';

import 'support/audio_fixture.dart';

/// Integrates the real handler and just_audio with a deterministic native bridge.
/// It verifies dispatch/order, not hardware or audio decoding.
class TestAudioPlatform extends JustAudioPlatform {
  final players = <String, TestPlayer>{};
  TestPlayer get active => players.values.last;
  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      players[request.id] = TestPlayer(request.id);
  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    await players.remove(request.id)?.events.close();
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async {
    for (final player in players.values) {
      await player.events.close();
    }
    players.clear();
    return DisposeAllPlayersResponse();
  }
}

class TestPlayer extends AudioPlayerPlatform {
  TestPlayer(super.id);
  final events = StreamController<PlaybackEventMessage>.broadcast();
  ProcessingStateMessage state = ProcessingStateMessage.idle;
  Duration position = Duration.zero;
  int loads = 0;
  void emit(ProcessingStateMessage next) {
    state = next;
    events.add(
      PlaybackEventMessage(
        icyMetadata: null,
        androidAudioSessionId: null,
        processingState: next,
        updateTime: DateTime.now(),
        updatePosition: position,
        bufferedPosition: const Duration(seconds: 60),
        duration: const Duration(seconds: 120),
        currentIndex: 0,
      ),
    );
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => events.stream;
  @override
  Future<LoadResponse> load(LoadRequest request) async {
    loads++;
    position = Duration.zero;
    emit(ProcessingStateMessage.loading);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    emit(ProcessingStateMessage.ready);
    return LoadResponse(duration: const Duration(seconds: 120));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async => PlayResponse();
  @override
  Future<PauseResponse> pause(PauseRequest request) async => PauseResponse();
  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    position = request.position ?? Duration.zero;
    emit(state);
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();
  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();
  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
    SetSkipSilenceRequest request,
  ) async => SetSkipSilenceResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();
  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
    SetShuffleOrderRequest request,
  ) async => SetShuffleOrderResponse();
  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
  setAutomaticallyWaitsToMinimizeStalling(
    SetAutomaticallyWaitsToMinimizeStallingRequest request,
  ) async => SetAutomaticallyWaitsToMinimizeStallingResponse();
}

class RecordingSources extends NativeExtensionService {
  int resolutions = 0;
  @override
  Future<ExtensionPackage> load(
    String id, {
    bool requireEnabled = true,
  }) async => ExtensionPackage(
    id: id,
    digest: 'fixture',
    source: '',
    licenses: {},
    manifest: {
      'name': id,
      'version': '1',
      'type': ['metadata_provider', 'download_provider'],
      'permissions': {
        'network': ['audio.example'],
      },
      'qualityOptions': [
        {'id': 'AAC_320', 'label': 'AAC 320 kbps'},
      ],
    },
  );
  @override
  Future<String?> playbackQuality(Map song, String tier) async => 'AAC_320';
  @override
  Future<Map<String, dynamic>> resolve(Map song, {String? quality}) async {
    resolutions++;
    return {
      'url': 'https://audio.example/track.m4a',
      'format': 'm4a',
      'quality': '320kbps',
      'headers': {'Authorization': 'private-provider-token'},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late File wav;
  late YazhalAudioHandler handler;
  late RecordingSources sources;
  late TestAudioPlatform platform;
  final original = JustAudioPlatform.instance;
  Map<String, dynamic> song(String id) => {
    'ytid': 'local:$id',
    'id': 'local:$id',
    'title': id,
    'artist': 'Test',
    'audioPath': wav.path,
    'isLive': false,
  };
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 350));
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('yazhal_sequence_integration');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
    wav = File('${dir.path}/track.wav');
    await wav.writeAsBytes(silentWav());
  });
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    platform = TestAudioPlatform();
    JustAudioPlatform.instance = platform;
    offlineMode.value = true;
    playNextSongAutomatically.value = false;
    shuffleNotifier.value = false;
    repeatNotifier.value = AudioServiceRepeatMode.none;
    userOfflineSongs.value = [
      for (final id in ['a', 'b', 'c', 'x', 'y', 'z']) song(id),
    ];
    sources = RecordingSources();
    handler = YazhalAudioHandler(
      sources: sources,
      cache: PlaybackCache(directory: Directory('${dir.path}/buffer')),
      metadataLookup: (_) async => <String, dynamic>{},
    );
    await settle();
  });
  tearDown(() async {
    await handler.stop();
    await handler.audioPlayer.dispose();
    await settle();
    JustAudioPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test('online provider playback starts without Download and does not persist HTTP secrets', () async {
    offlineMode.value = false;
    final online = {
      'id': 'ext:js:fixture:one',
      'ytid': 'ext:js:fixture:one',
      'source': 'js-extension',
      'extensionId': 'fixture',
      'providerTrackId': 'one',
      'providerTrack': {'id': 'one'},
      'title': 'Online',
      'artist': 'Test',
      'isLive': false,
    };
    await handler.playPlaylistSong(
      playlist: {
        'list': [online],
      },
      songIndex: 0,
    );
    await settle();
    expect(sources.resolutions, 1);
    expect(handler.audioPlayer.playing, true);
    expect(
      userOfflineSongs.value.any((s) => s['ytid'] == online['ytid']),
      false,
    );
    final recent = userRecentlyPlayed.value.whereType<Map>().firstWhere(
      (s) => s['ytid'] == online['ytid'],
    );
    expect(recent.containsKey('_extensionHeaders'), false);
    expect(handler.mediaItem.value?.extras?['resolvedQuality'], '320kbps');
  });

  test(
    'media Next and Previous follow tapped context without any manual queue',
    () async {
      await handler.playPlaylistSong(
        playlist: {
          'title': 'Context',
          'list': [song('a'), song('b'), song('c')],
        },
        songIndex: 1,
      );
      await settle();
      expect(handler.currentSong?['title'], 'b');
      expect(
        handler.playbackState.value.controls.map((c) => c.action),
        containsAll([MediaAction.skipToNext, MediaAction.skipToPrevious]),
      );
      await handler.skipToNext();
      await settle();
      expect(handler.currentSong?['title'], 'c');
      await handler.skipToPrevious();
      await settle();
      expect(handler.currentSong?['title'], 'b');
    },
  );
  test(
    'native completion drains manual priority then resumes context',
    () async {
      await handler.playPlaylistSong(
        playlist: {
          'title': 'Context',
          'list': [song('a'), song('b'), song('c')],
        },
        songIndex: 0,
      );
      await settle();
      await handler.addToQueue(song('x'));
      await handler.addToQueue(song('y'));
      await handler.addToQueue(song('z'), playNext: true);
      for (final expected in ['z', 'x', 'y', 'b', 'c']) {
        platform.active.emit(ProcessingStateMessage.completed);
        await settle();
        expect(handler.currentSong?['title'], expected);
      }
      platform.active.emit(ProcessingStateMessage.completed);
      await settle();
      expect(handler.currentSong?['title'], 'c');
    },
  );
  test(
    'reordered queue and individual removal drive the same media commands',
    () async {
      await handler.playPlaylistSong(
        playlist: {
          'list': [song('a'), song('b'), song('c')],
        },
        songIndex: 0,
      );
      await settle();
      await handler.reorderQueue(2, 1);
      await handler.skipToNext();
      await settle();
      expect(handler.currentSong?['title'], 'c');
      await handler.removeFromQueue(2);
      expect(handler.canSkipToNext, false);
      expect(handler.currentSong?['title'], 'c');
    },
  );
  test('transient playback error retries the same occurrence and restores position', () async {
    offlineMode.value = false;
    final downloaded = {
      ...song('a'),
      'ytid': 'downloaded01',
      'id': 'downloaded01',
    };
    userOfflineSongs.value = [downloaded, song('b')];
    await handler.playPlaylistSong(
      playlist: {
        'list': [downloaded, song('b')],
      },
      songIndex: 0,
    );
    await settle();
    final entry = handler.currentSong!['queueEntryId'];
    await handler.audioPlayer.seek(const Duration(seconds: 12));
    platform.active.events.addError(
      PlatformException(code: '500', message: 'Simulated network interruption'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    expect(handler.currentSong!['queueEntryId'], entry);
    expect(handler.currentSong!['ytid'], 'downloaded01');
    expect(handler.audioPlayer.position.inSeconds, greaterThanOrEqualTo(12));
    expect(handler.audioPlayer.playing, true);
  });
  test('user pause cancels pending automatic recovery', () async {
    offlineMode.value = false;
    final downloaded = {
      ...song('a'),
      'ytid': 'downloaded01',
      'id': 'downloaded01',
    };
    userOfflineSongs.value = [downloaded];
    await handler.playPlaylistSong(
      playlist: {
        'list': [downloaded],
      },
      songIndex: 0,
    );
    await settle();
    final loads = platform.active.loads;
    platform.active.events.addError(
      PlatformException(code: '500', message: 'Simulated network interruption'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await handler.pause();
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    expect(platform.active.loads, loads);
    expect(handler.audioPlayer.playing, false);
  });
  test(
    'prepare without playing retains intent when starting a new context',
    () async {
      expect(await handler.playSong(song('a'), playWhenReady: false), true);
      await settle();
      expect(handler.currentSong?['title'], 'a');
      expect(handler.audioPlayer.playing, false);
    },
  );
  test('manual songs queued before first playback are retained', () async {
    await handler.addPlaylistToQueue([song('x')]);
    await handler.playPlaylistSong(
      playlist: {
        'list': [song('a'), song('b')],
      },
      songIndex: 0,
    );
    await settle();
    await handler.skipToNext();
    await settle();
    expect(handler.currentSong?['title'], 'x');
    await handler.skipToNext();
    await settle();
    expect(handler.currentSong?['title'], 'b');
  });
  test(
    'ordinary online tracks cannot fall through to arbitrary native URLs',
    () async {
      final source = await handler.buildAudioSource(
        {...song('a'), 'ytid': 'video000001'},
        'https://127.0.0.1/private',
        false,
      );
      expect(source, isNull);
    },
  );
  test(
    'recovery follows entry identity when the current row is reordered',
    () async {
      offlineMode.value = false;
      final downloaded = {
        ...song('a'),
        'ytid': 'downloaded01',
        'id': 'downloaded01',
      };
      userOfflineSongs.value = [downloaded, song('b')];
      await handler.playPlaylistSong(
        playlist: {
          'list': [downloaded, song('b')],
        },
        songIndex: 0,
      );
      await settle();
      final entry = handler.currentSong!['queueEntryId'];
      await handler.audioPlayer.seek(const Duration(seconds: 15));
      platform.active.events.addError(
        PlatformException(code: '500', message: 'Simulated interruption'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await handler.reorderQueue(0, 1);
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      expect(handler.currentSong!['queueEntryId'], entry);
      expect(handler.audioPlayer.position.inSeconds, greaterThanOrEqualTo(15));
    },
  );
}
