import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/services/common_services.dart';
import 'package:yazhal/services/io_service.dart';
import 'package:yazhal/services/local_music_import_service.dart';
import 'package:yazhal/services/music_storage_service.dart';
import 'package:yazhal/services/playlist_download_service.dart';
import 'package:yazhal/services/playlists_manager.dart';
import 'package:yazhal/utilities/local_tracks.dart';
import 'package:yazhal/utilities/m3u_parser.dart';
import 'package:yazhal/utilities/mediaitem.dart';
import 'package:yazhal/utilities/recommendation_session.dart';

import 'support/audio_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('M3U parsing and safe path resolution', () {
    test(
      'BOM, CRLF, metadata, Unicode and repeated entries preserve order',
      () {
        final entries = parseM3u(
          '\uFEFF#EXTM3U\r\n#EXTINF:123,தமிழ்\r\n../音楽/track.mp3\r\n../音楽/track.mp3\r\n',
        );
        expect(entries.length, 2);
        expect(entries.first.title, 'தமிழ்');
        expect(entries.first.duration, 123);
        expect(entries.last.title, isNull);
        expect(
          resolvePlaylistEntry('playlists/a.m3u', entries.first.location),
          '音楽/track.mp3',
        );
      },
    );
    test(
      'rejects network references, absolute paths and escaping the chosen tree',
      () {
        for (final location in [
          'https://example.com/a.mp3',
          'content://x',
          '/secret.mp3',
          'C:/Music/a.mp3',
          '../../outside.mp3',
        ]) {
          expect(
            resolvePlaylistEntry('a.m3u', location),
            isNull,
            reason: location,
          );
        }
      },
    );
    test('explicit root remapping does not guess by basename', () {
      expect(
        resolvePlaylistEntry(
          'lists/a.m3u',
          r'C:\Music\album\song.mp3',
          originalRoot: r'C:\Music',
        ),
        'album/song.mp3',
      );
      expect(
        resolvePlaylistEntry(
          'lists/a.m3u',
          '/old/song.mp3',
          originalRoot: '/other',
        ),
        isNull,
      );
      expect(
        resolvePlaylistEntry(
          'lists/a.m3u',
          '/oldish/song.mp3',
          originalRoot: '/old',
        ),
        isNull,
      );
    });
    test('file URI root remapping decodes paths before matching', () {
      expect(
        resolvePlaylistEntry(
          'lists/a.m3u',
          'file:///old/My%20Song.mp3',
          originalRoot: '/old',
        ),
        'My Song.mp3',
      );
    });
    test(
      'bounds input size',
      () => expect(
        () => parseM3u('x' * (4 * 1024 * 1024 + 1)),
        throwsFormatException,
      ),
    );
    test('namespaced local IDs and safe actual-container filenames', () {
      expect(isLocalTrackId(MusicStorageService.localId('file:///a')), isTrue);
      final name = safeAudioFilename('../Artist: Title?', 'abc', 'webm');
      expect(name, endsWith('[abc].webm'));
      expect(isAudioFilename(name), isTrue);
      expect(
        isAudioFilename(safeAudioFilename('Track', 'abc', '3gpp')),
        isTrue,
      );
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(':')));
    });
  });

  group('recommendation sessions', () {
    test(
      'refresh excludes displayed tracks and keeps old songs on exhaustion',
      () async {
        final calls = <Set<String>>[];
        final session = RecommendationSession(
          limit: 2,
          load: (excluded, refresh) async {
            calls.add({...excluded});
            return [
              for (final id in ['a', 'b', 'c']) {'ytid': id},
            ];
          },
        );
        expect(await session.refresh(initial: true), isTrue);
        expect(session.songs.map((s) => s['ytid']), ['a', 'b']);
        expect(await session.refresh(), isTrue);
        expect(calls.last, {'a', 'b'});
        expect(session.songs.single['ytid'], 'c');
        expect(await session.refresh(), isFalse);
        expect(session.songs.single['ytid'], 'c');
      },
    );
    test('coalesces repeated taps and ignores a disposed request', () async {
      final pending = Completer<List<dynamic>>();
      var calls = 0;
      final session = RecommendationSession(
        limit: 2,
        load: (_, __) {
          calls++;
          return pending.future;
        },
      );
      final first = session.refresh();
      expect(await session.refresh(), isFalse);
      expect(calls, 1);
      session.dispose();
      pending.complete([
        {'ytid': 'a'},
      ]);
      expect(await first, isFalse);
      expect(session.songs, isEmpty);
    });
    test('network failure retains the last batch and permits retry', () async {
      var fail = false;
      final session = RecommendationSession(
        limit: 2,
        load: (_, __) async {
          if (fail) throw const SocketException('offline');
          return [
            {'ytid': 'a'},
          ];
        },
      );
      await session.refresh();
      fail = true;
      await expectLater(session.refresh(), throwsA(isA<SocketException>()));
      expect(session.songs.single['ytid'], 'a');
      expect(session.busy, isFalse);
    });
    test('excludes owned songs, duplicate IDs and invalid entries', () async {
      final session = RecommendationSession(
        limit: 5,
        load: (_, __) async => [
          {'ytid': 'owned'},
          {'ytid': 'a'},
          {'ytid': 'a'},
          {},
          null,
        ],
      );
      await session.refresh(excluded: {'owned'});
      expect(session.songs.map((s) => s['ytid']), ['a']);
    });
  });

  group('local music, playlists and ownership integration', () {
    late Directory temporary;
    late Directory music;
    setUpAll(() async {
      temporary = await Directory.systemTemp.createTemp('yazhal_custom');
      Hive.init('${temporary.path}/hive');
      for (final name in ['user', 'userNoBackup', 'settings', 'cache']) {
        await Hive.openBox(name);
      }
      applicationDirPath = '${temporary.path}/private';
    });
    setUp(() async {
      for (final name in ['user', 'userNoBackup', 'settings', 'cache']) {
        await Hive.box(name).clear();
      }
      userOfflineSongs.value = [];
      userCustomPlaylists.value = [];
      userPlaylistFolders.value = [];
      offlinePlaylistService.offlinePlaylists.value = [];
      music = await Directory('${temporary.path}/music').create();
      await File('${music.path}/one.wav').writeAsBytes(silentWav());
      await File('${music.path}/two.wav').writeAsBytes(silentWav());
      await File('${music.path}/set.m3u8').writeAsString(
        '#EXTM3U\none.wav\none.wav\nmissing.mp3\nhttps://example.com/file\ntwo.wav\n',
      );
    });
    tearDownAll(() async {
      await Hive.close();
      await temporary.delete(recursive: true);
    });
    test('preview reports missing entries; commit preserves order and repeat imports deduplicate', () async {
      final preview = await LocalMusicImportService.preview(music.path);
      expect(preview.songs, hasLength(2));
      expect(preview.issues, hasLength(2));
      expect(
        (preview.playlists.single['list'] as List).map((s) => s['title']),
        ['one', 'one', 'two'],
      );
      final result = await LocalMusicImportService.commit(preview);
      expect(result.added, 2);
      expect(result.playlists, 1);
      final again = await LocalMusicImportService.commit(preview);
      expect(again.added, 0);
      expect(again.skipped, 2);
      expect(again.playlists, 0);
      final track = userOfflineSongs.value.first as Map;
      expect(mapToMediaItem(track).artUri, isNull);
      expect(await MusicStorageService.playbackPath(track), endsWith('.wav'));
      expect(await makeSongOffline(track), isTrue);
      await removeSongFromOffline(track['ytid']);
      expect(await File('${music.path}/one.wav').exists(), isTrue);
      await offlinePlaylistService.deleteAllDownloads();
      expect(userOfflineSongs.value, hasLength(1));
      expect(await File('${music.path}/two.wav').exists(), isTrue);
    });
    test(
      'missing local IDs fail locally instead of querying an online provider',
      () async {
        await expectLater(getSongDetails(0, 'local:missing'), throwsStateError);
        expect(await fetchSongStreamUrl('local:missing', false), isNull);
        expect(await fetchBestAudioStream('local:missing'), isNull);
      },
    );
    test(
      'concurrent offline registry writes never drop completed tracks',
      () async {
        await Future.wait([
          for (var i = 0; i < 20; i++)
            MusicStorageService.mutateOfflineSongs(
              (current) =>
                  current..add({'ytid': 'job-$i', 'title': 'Track $i'}),
              onSaved: (next) => userOfflineSongs.value = next,
            ),
        ]);
        expect(
          (Hive.box('userNoBackup').get('offlineSongs') as List).length,
          20,
        );
        expect(userOfflineSongs.value.map((s) => s['ytid']).toSet().length, 20);
      },
    );
    test(
      'a rejected offline mutation does not poison subsequent writes',
      () async {
        await expectLater(
          MusicStorageService.mutateOfflineSongs(
            (_) => throw StateError('failed write'),
            onSaved: (_) {},
          ),
          throwsStateError,
        );
        await MusicStorageService.mutateOfflineSongs(
          (current) => current..add({'ytid': 'after-failure'}),
          onSaved: (next) => userOfflineSongs.value = next,
        );
        expect(userOfflineSongs.value.single['ytid'], 'after-failure');
      },
    );
    test('bulk removal uses canonical occurrence positions and persists folder playlists', () async {
      final a = {'ytid': 'a', 'title': 'Z'};
      final duplicate = {'ytid': 'a', 'title': 'A'};
      final b = {'ytid': 'b', 'title': 'B'};
      userPlaylistFolders.value = [
        {
          'ytid': 'folder',
          'playlists': [
            {
              'ytid': 'custom-test',
              'source': 'user-created',
              'list': [a, b, duplicate],
            },
          ],
        },
      ];
      await removeSongsFromCustomPlaylist('custom-test', {2});
      final list =
          (Hive.box('user').get(
                'playlistFolders',
              ) as List).single['playlists'].single['list']
              as List;
      expect(list.map((s) => s['title']), ['Z', 'B']);
      await expectLater(
        removeSongsFromCustomPlaylist('custom-test', {5}),
        throwsRangeError,
      );
    });
    test(
      'publishing uses a chosen destination and rejects overwrites',
      () async {
        final source = await File('${temporary.path}/staged.wav')
            .writeAsBytes(silentWav());
        final destination = await Directory('${temporary.path}/destination')
            .create();
        final uri = await MusicStorageService.publish(
          source,
          destination.path,
          'track.wav',
          'audio/wav',
        );
        expect(
          await File.fromUri(Uri.parse(uri)).readAsBytes(),
          await source.readAsBytes(),
        );
        await expectLater(
          MusicStorageService.publish(
            source,
            destination.path,
            'track.wav',
            'audio/wav',
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          await MusicStorageService.playbackPath({'audioUri': uri}),
          endsWith('track.wav'),
        );
      },
    );
  });
}
