import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/services/common_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  Map song(String id) => {'ytid': id, 'id': id, 'title': id, 'artist': 'Test'};
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('yazhal_favourites');
    Hive.init(dir.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });
  setUp(() async {
    userLikedSongsList.value = [];
    await Hive.box('user').clear();
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test(
    'local favourites deduplicate and remain on disk after reopening',
    () async {
      userLikedSongsList.value = [song('local:a'), song('local:a')];
      await updateSongLikeStatus('local:b', true, songData: song('local:b'));
      expect(userLikedSongsList.value.map((s) => s['ytid']), [
        'local:b',
        'local:a',
      ]);
      await Hive.box('user').close();
      await Hive.openBox('user');
      expect(
        (Hive.box('user').get('likedSongs') as List).map((s) => s['ytid']),
        ['local:b', 'local:a'],
      );
    },
  );
  test(
    'rapid heart toggles commit the most recent intent without duplicates',
    () async {
      await Future.wait([
        updateSongLikeStatus('local:a', true, songData: song('local:a')),
        updateSongLikeStatus('local:a', false),
        updateSongLikeStatus('local:a', true, songData: song('local:a')),
      ]);
      expect(userLikedSongsList.value.length, 1);
      expect((Hive.box('user').get('likedSongs') as List).length, 1);
      await updateSongLikeStatus('local:a', false);
      expect(userLikedSongsList.value, isEmpty);
      expect(Hive.box('user').get('likedSongs'), isEmpty);
    },
  );
  test(
    'concurrent favourites on different songs persist the combined result',
    () async {
      await Future.wait([
        updateSongLikeStatus('local:a', true, songData: song('local:a')),
        updateSongLikeStatus('local:b', true, songData: song('local:b')),
      ]);
      expect(userLikedSongsList.value.map((s) => s['ytid']).toSet(), {
        'local:a',
        'local:b',
      });
      expect((Hive.box('user').get('likedSongs') as List).length, 2);
    },
  );
}
