import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/services/common_services.dart';
import 'package:yazhal/services/extensions/extension_lyrics_service.dart';
import 'package:yazhal/services/extensions/extension_package.dart';
import 'package:yazhal/services/extensions/native_extension_service.dart';
import 'package:yazhal/services/io_service.dart';
import 'package:yazhal/services/lyrics/lyrics_models.dart';
import 'package:yazhal/services/lyrics/offline_lyrics_store.dart';
import 'package:yazhal/utilities/download_quality.dart';
import 'package:yazhal/utilities/mediaitem.dart';
import 'package:yazhal/utilities/provider_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('yazhal_extension_features');
    Hive.init(dir.path);
    for (final name in ['settings', 'cache', 'user', 'userNoBackup']) {
      await Hive.openBox(name);
    }
    applicationDirPath = dir.path;
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test(
    'Mornye line timing survives conversion and ignores supplement separators',
    () {
      final lyrics = ExtensionLyricsService.normalize({
        'plainLyrics': '',
        'syncType': 'LINE_SYNCED',
        'lines': [
          {'startTimeMs': '1500', 'words': 'First'},
          {'startTimeMs': 999999999, 'words': ''},
          {'startTimeMs': 3000, 'words': 'Second'},
        ],
      }, 'Jellyfin');
      expect(lyrics.isSynced, true);
      expect(lyrics.synced!.map((l) => l.start.inMilliseconds), [1500, 3000]);
      expect(lyrics.text, 'First\nSecond');
      expect(lyrics.source, 'Jellyfin');
    },
  );
  test('unsynced and instrumental provider responses remain usable', () {
    expect(
      ExtensionLyricsService.normalize({
        'syncType': 'UNSYNCED',
        'lines': [
          {'words': 'A'},
          {'words': 'B'},
        ],
      }, 'Source').text,
      'A\nB',
    );
    expect(
      ExtensionLyricsService.normalize({'instrumental': true}, 'Source').text,
      'Instrumental',
    );
  });
  test(
    'lyrics cache persists timing and attribution across reopening',
    () async {
      const track = TrackInfo(title: 'Test', artist: 'Artist', album: 'Album');
      await OfflineLyricsStore.save(
        track,
        const Lyrics(
          source: 'Original source',
          synced: [LyricLine(Duration(seconds: 2), 'Line')],
        ),
      );
      await Hive.box('cache').close();
      await Hive.openBox('cache');
      final cached = OfflineLyricsStore.read(track)!;
      expect(cached.source, 'Original source');
      expect(cached.synced!.single.start, const Duration(seconds: 2));
    },
  );
  test(
    'provider identity and full metadata survive queue media conversion',
    () {
      final track = NativeExtensionService.normalizeTrack('jiosaavn', {
        'id': 'abc',
        'name': 'Track',
        'artists': [
          {'name': 'Artist'},
        ],
        'album_name': 'Album',
        'duration_ms': 120000,
        'isrc': 'TEST123',
      });
      final roundtrip = mediaItemToMap(mapToMediaItem(track));
      expect(roundtrip['providerTrackId'], 'abc');
      expect((roundtrip['providerTrack'] as Map)['isrc'], 'TEST123');
      expect(roundtrip['source'], 'js-extension');
      expect(downloadSourceKey(track), 'js:jiosaavn');
    },
  );
  test(
    'wildcard provider permissions still reject localhost and plain HTTP',
    () {
      final p = ExtensionPackage(
        id: 'wild',
        manifest: {
          'permissions': {
            'network': ['*'],
          },
        },
        source: '',
        digest: '',
        licenses: {},
      );
      expect(p.allows(Uri.parse('https://example.org')), true);
      expect(p.allows(Uri.parse('https://127.0.0.1')), false);
      expect(p.allows(Uri.parse('http://example.org')), false);
    },
  );
  test('cross-source download keeps metadata identity and stores actual audio provenance', () async {
    final original = NativeExtensionService.normalizeTrack('metadata', {
      'id': 'meta-id',
      'name': 'Original title',
      'artist': 'Original artist',
    });
    final audio = NativeExtensionService.normalizeTrack('audio', {
      'id': 'audio-id',
      'name': 'Audio title',
      'artist': 'Original artist',
    });
    final service = _FakeAudioSource();
    final success = await makeSongOffline(
      original,
      quality: 'AAC_96',
      downloadTrack: audio,
      sourceService: service,
    );
    expect(success, true);
    expect(service.quality, 'AAC_96');
    expect(service.downloadedProvider, 'audio');
    final stored = getOfflineSongByYtid(original['ytid']);
    expect(stored['title'], 'Original title');
    expect(stored['downloadSourceId'], 'audio');
    expect(stored['audioCodec'], 'aac');
    expect(stored['audioPath'], endsWith('.m4a'));
    expect(await File(stored['audioPath'].toString()).exists(), true);
  });
  test('provider artwork cannot bypass private-URL or credential guards', () {
    final safe = NativeExtensionService.normalizeTrack('source', {
      'id': 'one',
      'name': 'Title',
      'cover_url': 'https://images.example.org/cover.jpg',
    });
    expect(
      Uri.parse(safe['highResImage'].toString()).scheme,
      providerArtworkScheme,
    );
    final private = NativeExtensionService.normalizeTrack('source', {
      'id': 'two',
      'name': 'Title',
      'cover_url': 'https://127.0.0.1/private',
    });
    expect(private['highResImage'], '');
    final secret = NativeExtensionService.normalizeTrack('source', {
      'id': 'three',
      'name': 'Title',
      'cover_url': 'https://images.example.org/cover.jpg?api_key=secret',
      'access_token': 'secret',
    });
    expect(secret['highResImage'], '');
    expect((secret['providerTrack'] as Map).containsKey('access_token'), false);
  });
}

class _FakeAudioSource extends NativeExtensionService {
  String? quality, downloadedProvider;
  @override
  Future<Map<String, dynamic>> resolve(Map song, {String? quality}) async {
    this.quality = quality;
    return {
      'url': 'https://example.org/audio.m4a',
      'format': 'm4a',
      'audio_codec': 'aac',
      'quality': '96kbps',
      'selectedQuality': quality,
    };
  }

  @override
  Future<void> download(Map song, Map resolved, File target) async {
    downloadedProvider = song['extensionId'].toString();
    await target.writeAsBytes([
      0,
      0,
      0,
      16,
      102,
      116,
      121,
      112,
      77,
      52,
      65,
      32,
      0,
      0,
      0,
      0,
    ]);
  }
}
