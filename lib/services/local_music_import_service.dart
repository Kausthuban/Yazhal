import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/services/common_services.dart';
import 'package:yazhal/services/music_storage_service.dart';
import 'package:yazhal/services/playlists_manager.dart';
import 'package:yazhal/utilities/local_tracks.dart';
import 'package:yazhal/utilities/m3u_parser.dart';

class LocalImportPreview {
  LocalImportPreview(this.songs, this.playlists, this.issues);
  final List<Map<String, dynamic>> songs;
  final List<Map<String, dynamic>> playlists;
  final List<String> issues;
}

class LocalMusicImportService {
  static Future<LocalImportPreview> preview(
    String folder, {
    String? originalRoot,
  }) async {
    final entries = await MusicStorageService.scan(folder);
    final songsByPath = <String, Map<String, dynamic>>{};
    final issues = <String>[];
    for (final entry in entries.where(
      (e) => isAudioFilename(e['name'] as String),
    )) {
      songsByPath[entry['relativePath'] as String] =
          MusicStorageService.localSong(entry);
    }
    final playlists = <Map<String, dynamic>>[];
    for (final entry in entries.where(
      (e) => isPlaylistFilename(e['name'] as String),
    )) {
      try {
        final songs = <Map<String, dynamic>>[];
        final parsed = parseM3u(
          await MusicStorageService.readText(entry['uri'] as String),
        );
        for (final item in parsed) {
          final path = resolvePlaylistEntry(
            entry['relativePath'] as String,
            item.location,
            originalRoot: originalRoot,
          );
          final song = songsByPath[path];
          if (song == null) {
            issues.add('${entry['name']}: ${item.location}');
            continue;
          }
          songs.add({
            ...song,
            if (item.title?.isNotEmpty == true && song['artist'] == '')
              'title': item.title,
            if (song['duration'] == null &&
                item.duration != null &&
                item.duration! > 0)
              'duration': item.duration,
          });
        }
        playlists.add({
          'ytid':
              'custom-import-${MusicStorageService.localId(entry['uri'] as String).substring(6)}',
          'title': (entry['name'] as String).replaceFirst(
            RegExp(r'\.[^.]+$'),
            '',
          ),
          'source': 'user-created',
          'list': songs,
          'importedPlaylist': true,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (e) {
        issues.add('${entry['name']}: $e');
      }
    }
    return LocalImportPreview(songsByPath.values.toList(), playlists, issues);
  }

  /// Merge files; never replace an edited personal playlist on a repeated import.
  static Future<void> _imports = Future.value();
  static Future<({int added, int skipped, int playlists})> commit(
    LocalImportPreview preview,
  ) {
    final operation = _imports.then((_) => _commit(preview));
    _imports = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  static Future<({int added, int skipped, int playlists})> _commit(
    LocalImportPreview preview,
  ) async {
    var added = 0;
    // Publish notifier state only after successful storage writes.
    await MusicStorageService.mutateOfflineSongs((current) {
      final ids = current.map((s) => s['ytid']).toSet();
      for (final song in preview.songs) {
        if (ids.add(song['ytid'])) {
          current.add(song);
          added++;
        } else if (song['artworkPath'] != null) {
          final index = current.indexWhere((s) => s['ytid'] == song['ytid']);
          if (index >= 0 && current[index]['artworkPath'] == null) {
            current[index] = {
              ...Map<String, dynamic>.from(current[index] as Map),
              'artworkPath': song['artworkPath'],
            };
          }
        }
      }
      return current;
    }, onSaved: (next) => userOfflineSongs.value = next);
    // Read playlists after file writes; an automatic scan must not publish a
    // snapshot captured before a user edited their playlists. Rebase on changes
    // while the storage write is in flight. Re-scans with no additions do not
    // rewrite playlists at all.
    var count = 0;
    while (preview.playlists.isNotEmpty) {
      final baseline = userCustomPlaylists.value;
      final ids = getUserCustomPlaylists().map((p) => p['ytid']).toSet();
      final additions = preview.playlists
          .where((p) => ids.add(p['ytid']))
          .toList();
      if (additions.isEmpty) break;
      final custom = <Map>[...baseline, ...additions];
      await Hive.box('user').put('customPlaylists', custom);
      if (!identical(userCustomPlaylists.value, baseline)) continue;
      userCustomPlaylists.value = custom;
      count = additions.length;
      break;
    }
    return (
      added: added,
      skipped: preview.songs.length - added,
      playlists: count,
    );
  }
}
