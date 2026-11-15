import 'package:flutter_test/flutter_test.dart';
import 'package:yazhal/services/catalog_metadata_service.dart';
import 'package:yazhal/services/headset_gestures.dart';
import 'package:yazhal/services/listening_activity.dart';
import 'package:yazhal/utilities/listening_profile.dart';

void main() {
  test(
    'two recent Tamil songs outweigh older English history for discovery',
    () {
      final profile = ListeningProfile([
        {'title': 'Tamil one', 'artist': 'Anirudh', 'language': 'tamil'},
        {'title': 'Tamil two', 'artist': 'A R Rahman', 'language': 'ta'},
        for (var i = 0; i < 100; i++)
          {
            'title': 'English $i',
            'artist': 'Older artist',
            'language': 'english',
            'listeningCount': 100,
          },
      ]);
      expect(profile.language, 'tamil');
      expect(profile.queries.every((q) => q.contains('tamil')), true);
      final ranked = profile.rank([
        {'ytid': 'en', 'artist': 'Unknown', 'language': 'english'},
        {'ytid': 'ta', 'artist': 'Anirudh', 'language': 'tamil'},
      ]);
      expect(ranked.first['ytid'], 'ta');
    },
  );
  test('Tamil script works without guessing language from a person name', () {
    expect(ListeningProfile.languageOf({'title': 'தமிழ் பாடல்'}), 'tamil');
    expect(
      ListeningProfile.languageOf({'title': 'Song', 'artist': 'Anirudh'}),
      isNull,
    );
  });
  test('frequent playlists and songs rank by actual listening counts', () {
    expect(
      ListeningActivity.frequentPlaylists(
        [
          {'ytid': 'a'},
          {'ytid': 'b'},
        ],
        {'b': 20, 'a': 2},
      ).first['ytid'],
      'b',
    );
    expect(
      ListeningActivity.frequentSongs([
        {'ytid': 'a', 'listeningCount': 1},
        {'ytid': 'b', 'listeningCount': 3},
      ]).first['ytid'],
      'b',
    );
  });
  test('artwork matches artist and duration and refuses YouTube URLs', () {
    final song = {'title': 'My song', 'artist': 'My artist', 'duration': 180};
    final rows = [
      {
        'trackName': 'My song',
        'artistName': 'Other person',
        'trackTimeMillis': 180000,
        'artworkUrl100': 'https://is1-ssl.mzstatic.com/art/100x100bb.jpg',
      },
      {
        'trackName': 'My song',
        'artistName': 'My artist',
        'trackTimeMillis': 180000,
        'artworkUrl100': 'https://is1-ssl.mzstatic.com/art/100x100bb.jpg',
        'primaryGenreName': 'Tamil',
      },
    ];
    expect(
      CatalogMetadataService.match(song, rows)['catalogArtwork'],
      'https://is1-ssl.mzstatic.com/art/600x600bb.jpg',
    );
    expect(CatalogMetadataService.match(song, [rows.first]), isEmpty);
    expect(cleanArtwork('https://i.ytimg.com/vi/id/default.jpg'), '');
    expect(cleanArtwork('https://is1-ssl.mzstatic.com/art.jpg'), isNotEmpty);
  });
  test(
    'single/double/triple defaults and four-tap custom pattern are distinct',
    () {
      expect(resolveHeadsetPattern([0], {}), 'toggle');
      expect(resolveHeadsetPattern([0, 150], {}), 'next');
      expect(resolveHeadsetPattern([0, 150, 300], {}), 'previous');
      expect(
        resolveHeadsetPattern(
          [0, 160, 320, 480],
          {
            'headsetPattern': [0, 150, 300, 450],
            'headsetPatternAction': 'seekBackward',
          },
        ),
        'seekBackward',
      );
      expect(
        resolveHeadsetPattern(
          [0, 150, 300],
          {
            'headsetPattern': [0, 150, 300],
            'headsetPatternAction': 'seekForward',
          },
        ),
        'previous',
      );
      expect(
        resolveHeadsetPattern(
          [0, 800, 1600, 2400],
          {
            'headsetPattern': [0, 800, 1600, 2400],
          },
        ),
        'none',
      );
    },
  );
}
