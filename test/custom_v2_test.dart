import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yazhal/services/common_services.dart';
import 'package:yazhal/services/flac_extension_service.dart';
import 'package:yazhal/services/io_service.dart';
import 'package:yazhal/services/local_music_import_service.dart';
import 'package:yazhal/services/music_folder_service.dart';
import 'package:yazhal/services/offline_metadata_service.dart';
import 'package:yazhal/services/offline_taste_service.dart';
import 'package:yazhal/services/playlists_manager.dart'
    show userCustomPlaylists;
import 'package:yazhal/services/settings_manager.dart';
import 'package:yazhal/utilities/local_tracks.dart';
import 'package:yazhal/utilities/mediaitem.dart';
import 'package:yazhal/utilities/offline_play_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('yazhal_v2_');
    Hive.init(temp.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
    applicationDirPath = temp.path;
  });
  tearDown(() async {
    MusicFolderService.foreground(false);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.box(name).clear();
    }
    userOfflineSongs.value = [];
    offlineMode.value = false;
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test(
    'scan commits preserve playlist edits made while offline files are saved',
    () async {
      userCustomPlaylists.value = [];
      void editDuringScan() {
        userCustomPlaylists.value = [
          {
            'ytid': 'custom-kept',
            'title': 'Edited during scan',
            'source': 'user-created',
            'list': <dynamic>[],
          },
        ];
      }

      userOfflineSongs.addListener(editDuringScan);
      try {
        await LocalMusicImportService.commit(LocalImportPreview([], [], []));
        expect(userCustomPlaylists.value.single['title'], 'Edited during scan');
        final result = await LocalMusicImportService.commit(
          LocalImportPreview([], [
            {
              'ytid': 'custom-import-new',
              'title': 'Imported',
              'source': 'user-created',
              'list': <dynamic>[],
            },
          ], []),
        );
        expect(result.playlists, 1);
        expect(
          userCustomPlaylists.value.map((p) => p['title']),
          containsAll(['Edited during scan', 'Imported']),
        );
      } finally {
        userOfflineSongs.removeListener(editDuringScan);
        userCustomPlaylists.value = [];
      }
    },
  );
  test(
    'FLAC source survives media item conversions for queue and player menus',
    () {
      final song = {
        'id': 'ext:catalog:abc',
        'ytid': 'ext:catalog:abc',
        'source': 'extension',
        'extensionId': 'catalog',
        'streamUrl': 'https://audio.example/track.flac',
        'format': 'flac',
        'title': 'Track',
        'artist': 'Artist',
      };
      final roundTrip = mediaItemToMap(mapToMediaItem(song));
      expect(roundTrip['streamUrl'], song['streamUrl']);
      expect(roundTrip['extensionId'], 'catalog');
      expect(roundTrip['source'], 'extension');
      expect(roundTrip['ytid'], 'ext:catalog:abc');
    },
  );
  test('only a matching file source that actually starts is recorded once', () {
    final session = OfflinePlaySession();
    final song = {'ytid': 'local:a', 'title': 'Track'};
    session.prepare(song, offline: true);
    expect(
      session.takeStarted(playing: false, ready: true, sourceId: 'local:a'),
      isNull,
    );
    expect(
      session.takeStarted(playing: true, ready: false, sourceId: 'local:a'),
      isNull,
    );
    expect(
      session.takeStarted(playing: true, ready: true, sourceId: 'local:stale'),
      isNull,
    );
    expect(
      session.takeStarted(
        playing: true,
        ready: true,
        sourceId: 'local:a',
      )?['title'],
      'Track',
    );
    expect(
      session.takeStarted(playing: true, ready: true, sourceId: 'local:a'),
      isNull,
    );
    session.replay();
    expect(
      session.takeStarted(playing: false, ready: true, sourceId: 'local:a'),
      isNull,
    );
    expect(
      session.takeStarted(playing: true, ready: true, sourceId: 'local:a'),
      isNotNull,
    );
    session
      ..prepare(song, offline: false)
      ..replay();
    expect(
      session.takeStarted(playing: true, ready: true, sourceId: 'local:a'),
      isNull,
    );
  });
  test(
    'offline history serializes plays, strips file paths, and honors opt-out',
    () async {
      final song = {
        'ytid': 'local:a',
        'artist': 'Artist',
        'title': 'Track',
        'sourceUri': 'secret-path',
      };
      await Future.wait([
        OfflineTasteService.record(song),
        OfflineTasteService.record(song),
      ]);
      expect(OfflineTasteService.history.single['plays'], 2);
      expect(
        OfflineTasteService.history.single.containsKey('sourceUri'),
        false,
      );
      await Hive.box('settings').put('offlineTasteEnabled', false);
      await OfflineTasteService.record(song);
      expect(OfflineTasteService.history.single['plays'], 2);
      await OfflineTasteService.clear();
      expect(OfflineTasteService.history, isEmpty);
    },
  );
  test('library plus repeated offline plays influence ranking and discovery queries', () {
    final profile = OfflineTasteProfile(
      [
        {'artist': 'North', 'album': 'A'},
      ],
      [
        {
          'ytid': 'local:x',
          'artist': 'South',
          'plays': 20,
          'lastPlayed': DateTime.now().millisecondsSinceEpoch,
        },
      ],
    );
    expect(
      profile.rank([
        {'artist': 'Unrelated'},
        {'artist': 'SOUTH'},
      ]).first['artist'],
      'SOUTH',
    );
    expect(profile.discoveryQueries, contains('south music'));
    expect(profile.discoveryQueries.length, lessThanOrEqualTo(3));
    expect(profile.discoveryQueries.any((q) => q.contains('local:')), false);
  });
  test('offline recommendations never need a network provider', () async {
    offlineMode.value = true;
    userOfflineSongs.value = [
      {'ytid': 'local:a', 'artist': 'Artist', 'title': 'A'},
      {'ytid': 'local:b', 'artist': 'Artist', 'title': 'B'},
    ];
    expect(
      (await getRecommendedSongs(excludedIds: {'local:a'})).single['ytid'],
      'local:b',
    );
  });
  test('MusicBrainz parser handles artist joins, missing releases, and invalid IDs', () {
    final matches = MetadataCandidate.parse({
      'recordings': [
        {
          'id': '6f7d1f14-5a6c-4127-ab0d-0f1111111111',
          'title': 'Track',
          'artist-credit': [
            {'name': 'A', 'joinphrase': ' & '},
            {
              'artist': {'name': 'B'},
            },
          ],
          'releases': [
            {'id': 'c1111111-1111-1111-1111-111111111111', 'title': 'Album'},
          ],
        },
        {'id': '../../escape', 'title': 'Bad'},
        {'id': 'a1111111-1111-1111-1111-111111111111', 'title': 'Single'},
      ],
    });
    expect(matches.length, 2);
    expect(matches.first.artist, 'A & B');
    expect(matches.first.releaseId, isNotNull);
    expect(matches.last.releaseId, isNull);
  });
  test('metadata query uses filename artist and escapes Lucene controls', () {
    final query = OfflineMetadataService.query({
      'title': 'Artist - Song: (Live)',
    });
    expect(query, contains('artist:"Artist"'));
    expect(query, isNot(contains('(Live)')));
  });
  test(
    'metadata search caches duplicate searches and identifies app',
    () async {
      var calls = 0;
      final service = OfflineMetadataService(
        spacing: Duration.zero,
        client: MockClient((r) async {
          calls++;
          expect(r.url.host, 'musicbrainz.org');
          expect(r.headers['User-Agent'], contains('Yazhal/'));
          return http.Response('{"recordings":[]}', 200);
        }),
      );
      await Future.wait([
        service.search({'title': 'Track'}),
        service.search({'title': 'Track'}),
      ]);
      expect(calls, 1);
    },
  );
  test('missing artwork still saves confirmed metadata and preserves identity and ownership', () async {
    userOfflineSongs.value = [
      {
        'ytid': 'local:a',
        'title': 'Old',
        'sourceUri': 'content://original',
        'fileOwnership': 'imported',
      },
    ];
    await Hive.box('userNoBackup').put('offlineSongs', userOfflineSongs.value);
    final service = OfflineMetadataService(
      client: MockClient((_) async => http.Response('', 404)),
    );
    final result = await service.apply(
      'local:a',
      MetadataCandidate(
        title: 'New',
        artist: 'Artist',
        album: 'Album',
        recordingId: 'a1111111-1111-1111-1111-111111111111',
        releaseId: 'b1111111-1111-1111-1111-111111111111',
      ),
    );
    expect(result.artwork, false);
    final saved = userOfflineSongs.value.single;
    expect(saved['title'], 'New');
    expect(saved['sourceUri'], 'content://original');
    expect(saved['fileOwnership'], 'imported');
  });
  test(
    'confirmed cover art is cached privately without rewriting the music file',
    () async {
      final original = await File('${temp.path}/original.mp3')
          .writeAsBytes([1, 2, 3, 4]);
      userOfflineSongs.value = [
        {
          'ytid': 'local:cover',
          'title': 'Old',
          'sourceUri': original.uri.toString(),
          'fileOwnership': 'imported',
        },
      ];
      await Hive.box('userNoBackup')
          .put('offlineSongs', userOfflineSongs.value);
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7V8AAAAASUVORK5CYII=',
      );
      final service = OfflineMetadataService(
        client: MockClient((request) async {
          expect(request.url.host, 'coverartarchive.org');
          return http.Response.bytes(
            png,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      final result = await service.apply(
        'local:cover',
        MetadataCandidate(
          title: 'New',
          artist: 'Artist',
          album: 'Album',
          recordingId: 'a1111111-1111-1111-1111-111111111111',
          releaseId: 'b1111111-1111-1111-1111-111111111111',
        ),
      );
      expect(result.artwork, true);
      final artwork = File(
        userOfflineSongs.value.single['artworkPath'] as String,
      );
      expect(await artwork.readAsBytes(), png);
      expect(await original.readAsBytes(), [1, 2, 3, 4]);
    },
  );

  Map<String, dynamic> manifest() => {
    'schemaVersion': 1,
    'id': 'catalog',
    'name': 'Test catalog',
    'searchUrl': 'https://catalog.example/search?q={query}',
    'allowedHosts': ['catalog.example', 'audio.example'],
  };
  test(
    'extension manifests reject scripts, HTTP, credentials and host mismatches',
    () {
      final parsed = FlacExtension.parse(manifest());
      expect(parsed.enabled, false);
      for (final url in [
        'http://catalog.example?q={query}',
        'https://user:pass@catalog.example?q={query}',
        'https://evil.example?q={query}',
        'javascript:{query}',
      ]) {
        expect(
          () => FlacExtension.parse({...manifest(), 'searchUrl': url}),
          throwsFormatException,
        );
      }
      expect(
        parsed.allows(Uri.parse('https://catalog.example.evil.com/song.flac')),
        false,
      );
      expect(parsed.allows(Uri.parse('https://audio.example/song.flac')), true);
    },
  );
  test('FLAC catalog filters mislabeled formats and undeclared hosts', () {
    final source = FlacExtension.parse(manifest());
    expect(
      FlacExtensionService.track(source, {
        'title': 'A',
        'format': 'mp3',
        'audioUrl': 'https://audio.example/a.mp3',
      }),
      isNull,
    );
    expect(
      FlacExtensionService.track(source, {
        'title': 'A',
        'format': 'flac',
        'audioUrl': 'https://other.example/a.flac',
      }),
      isNull,
    );
    final song = FlacExtensionService.track(source, {
      'title': 'A',
      'format': 'flac',
      'audioUrl': 'https://audio.example/a.flac',
    })!;
    expect(isExtensionTrack(song), true);
    expect(isNonYoutubeId(song['ytid']), true);
    expect(isLocalTrack(song), false);
  });
  test('install defaults to disabled, supports enable/uninstall', () async {
    final source = FlacExtension.parse(manifest());
    await FlacExtensionService.install(source);
    expect(FlacExtensionService.extensions.last.enabled, false);
    await FlacExtensionService.enable(source, true);
    expect(FlacExtensionService.extensions.last.enabled, true);
    await FlacExtensionService.remove(source.id);
    expect(FlacExtensionService.extensions.length, 1);
    expect(FlacExtensionService.extensions.single.enabled, false);
  });
  test('download verifies FLAC bytes, not the filename', () async {
    final source = FlacExtension.parse(manifest());
    await FlacExtensionService.install(source);
    await FlacExtensionService.enable(source, true);
    final song = FlacExtensionService.track(source, {
      'title': 'Track',
      'format': 'flac',
      'audioUrl': 'https://audio.example/fake.flac',
    })!;
    final bad = FlacExtensionService(
      client: MockClient((_) async => http.Response('ID3this-is-mp3', 200)),
    );
    await expectLater(
      bad.download(song, File('${temp.path}/bad.partial')),
      throwsFormatException,
    );
    final good = FlacExtensionService(
      client: MockClient(
        (_) async =>
            http.Response.bytes([0x66, 0x4c, 0x61, 0x43, 0, 0, 0, 0], 200),
      ),
    );
    final file = File('${temp.path}/good.partial');
    await good.download(song, file);
    expect(FlacExtensionService.flacMagic(await file.readAsBytes()), true);
  });
  test(
    'built-in archive search expands real FLAC files from item metadata',
    () async {
      final source = FlacExtension(
        id: 'archive',
        name: 'Live Music Archive',
        searchUrl: 'https://archive.org/advancedsearch.php?q={query}',
        hosts: ['archive.org'],
        builtIn: true,
        enabled: true,
      );
      final service = FlacExtensionService(
        client: MockClient((request) async {
          if (request.url.path == '/advancedsearch.php') {
            expect(
              request.url.queryParameters['q'],
              contains('collection:etree'),
            );
            expect(
              request.url.queryParameters['q'],
              isNot(contains('mediatype:audio')),
            );
            return http.Response(
              '{"response":{"docs":[{"identifier":"show-1","title":"Concert","creator":"Band"}]}}',
              200,
            );
          }
          expect(request.url.path, '/metadata/show-1');
          return http.Response(
            '{"files":[{"name":"01 Song.flac","title":"Song"},{"name":"01 Song.mp3"}]}',
            200,
          );
        }),
      );
      final songs = await service.search(source, 'Band');
      expect(songs.length, 1);
      expect(
        songs.single['streamUrl'],
        'https://archive.org/download/show-1/01%20Song.flac',
      );
      expect(songs.single['format'], 'flac');
      expect(songs.single['artist'], 'Band');
    },
  );
  test(
    'disabled source cannot fetch or download and makes no HTTP request',
    () async {
      var calls = 0;
      final source = FlacExtension.parse(manifest());
      final service = FlacExtensionService(
        client: MockClient((_) async {
          calls++;
          return http.Response('', 200);
        }),
      );
      await expectLater(service.search(source, 'Artist'), throwsStateError);
      expect(calls, 0);
    },
  );
  test('redirects to undeclared audio hosts are rejected', () async {
    final source = FlacExtension.parse(manifest());
    final service = FlacExtensionService(
      client: MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'https://outside.example/audio.flac'},
        ),
      ),
    );
    await expectLater(
      service.open(source, Uri.parse('https://audio.example/file.flac')),
      throwsFormatException,
    );
  });
  test('multiple folders preserve switches, deduplicate, and never delete originals', () async {
    final dir = await Directory('${temp.path}/Music').create();
    final file = await File('${dir.path}/a.mp3').writeAsBytes([1, 2, 3]);
    await MusicFolderService.add(dir.path);
    await MusicFolderService.add(dir.path);
    await MusicFolderService.add('${temp.path}/Other');
    expect(MusicFolderService.folders.length, 2);
    await MusicFolderService.update(dir.path, {'enabled': false});
    expect(MusicFolderService.folders.first['enabled'], false);
    await MusicFolderService.scanAutomatic(); // disabled globally: does not touch nonexistent Other
    expect(MusicFolderService.folders.last['error'], null);
    await MusicFolderService.scan(dir.path);
    expect(userOfflineSongs.value.single['title'], 'a');
    await MusicFolderService.remove(dir.path);
    expect(await file.exists(), true);
    expect(userOfflineSongs.value.length, 1);
  });
  test(
    'automatic scanner skips disabled folders and records errors independently',
    () async {
      await MusicFolderService.add('${temp.path}/unavailable-one');
      await MusicFolderService.add('${temp.path}/unavailable-two');
      await MusicFolderService.update('${temp.path}/unavailable-one', {
        'enabled': false,
      });
      await Hive.box('settings').put('autoScanMusicFolders', true);
      await MusicFolderService.scanAutomatic();
      expect(MusicFolderService.folders.first['error'], isNull);
      expect(MusicFolderService.folders.last['error'], contains('unavailable'));
    },
  );
}
