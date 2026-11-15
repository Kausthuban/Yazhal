import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/utilities/local_tracks.dart';

/// Android document trees and desktop folders share this narrow I/O boundary.
class MusicStorageService {
  static const channel = MethodChannel('yazhal/music_storage');
  static String? get downloadFolder =>
      Hive.box('userNoBackup').get('downloadFolder') as String?;

  // Playlist download workers and import/metadata writes share one registry.
  // Serialize read-modify-write operations so one completed song cannot erase
  // another worker's entry while Hive is flushing the previous write.
  static Future<void> _offlineWrites = Future.value();
  static Future<List<dynamic>> mutateOfflineSongs(
    List<dynamic> Function(List<dynamic>) update, {
    required void Function(List<dynamic>) onSaved,
  }) {
    final operation = _offlineWrites.then((_) async {
      final box = Hive.box('userNoBackup');
      final current = List<dynamic>.from(
        box.get('offlineSongs', defaultValue: <dynamic>[]) as List,
      );
      final next = update(current);
      await box.put('offlineSongs', next);
      onSaved(next);
      return next;
    });
    _offlineWrites = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  static Future<String?> pickFolder() async {
    if (Platform.isAndroid) return channel.invokeMethod<String>('pickTree');
    return FilePicker.getDirectoryPath();
  }

  static Future<List<Map<String, dynamic>>> scan(String folder) async {
    if (Platform.isAndroid) {
      final raw =
          await channel.invokeListMethod<dynamic>('scanTree', {
            'tree': folder,
          }) ??
          [];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final result = <Map<String, dynamic>>[];
    final root = Directory(folder).absolute.path;
    await for (final entity in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!isAudioFilename(entity.path) && !isPlaylistFilename(entity.path))
        continue;
      result.add({
        'uri': entity.uri.toString(),
        'relativePath': entity.path
            .substring(root.length + 1)
            .replaceAll('\\', '/'),
        'name': entity.uri.pathSegments.last,
      });
      if (result.length > 20000)
        throw const FormatException('Folder exceeds 20,000 files');
    }
    return result;
  }

  static Future<String> readText(String uri) async {
    if (uri.startsWith('content:'))
      return (await channel.invokeMethod<String>('readText', {'uri': uri}))!;
    final file = File.fromUri(Uri.parse(uri));
    if (await file.length() > 4 * 1024 * 1024)
      throw const FormatException('Playlist exceeds 4 MiB');
    return file.readAsString();
  }

  /// Document providers are played through a disposable private cache. The
  /// original document is revalidated on every access (including after reboot).
  static Future<String?> playbackPath(
    Map song, {
    bool directPlayback = false,
  }) async {
    final uri = song['sourceUri']?.toString() ?? song['audioUri']?.toString();
    if (uri != null && uri.isNotEmpty) {
      if (uri.startsWith('content:')) {
        return channel.invokeMethod<String>(
          directPlayback ? 'preparePlaybackUri' : 'preparePlayback',
          {'uri': uri},
        );
      }
      final file = uri.startsWith('file:')
          ? File.fromUri(Uri.parse(uri))
          : File(uri);
      return await file.exists() ? file.path : null;
    }
    final path = song['audioPath']?.toString();
    return path != null && await File(path).exists() ? path : null;
  }

  /// Publish only completed downloads; preserve old private downloads in place.
  static Future<String> publish(
    File staging,
    String folder,
    String name,
    String mime,
  ) async {
    if (Platform.isAndroid) {
      return (await channel.invokeMethod<String>('publishDownload', {
        'tree': folder,
        'path': staging.path,
        'name': name,
        'mime': mime,
      }))!;
    }
    final target = File('$folder/$name');
    if (await target.exists())
      throw FileSystemException('Destination already exists', target.path);
    final partial = File('${target.path}.partial');
    try {
      await staging.copy(partial.path);
      await partial.rename(target.path);
      return target.uri.toString();
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  static String localId(String uri) =>
      'local:${sha256.convert(utf8.encode(uri))}';

  static Map<String, dynamic> localSong(Map<String, dynamic> entry) {
    final uri = entry['uri'] as String;
    final name = entry['name'] as String;
    final id = localId(uri);
    return {
      'ytid': id,
      'id': id,
      'source': 'local',
      'sourceUri': uri,
      'fileOwnership': 'imported',
      'title': entry['title'] ?? name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
      'artist': entry['artist'] ?? '',
      'album': entry['album'] ?? '',
      'duration': entry['duration'],
      if (entry['artworkPath'] != null) 'artworkPath': entry['artworkPath'],
      'isLive': false,
      'dateAdded': DateTime.now().millisecondsSinceEpoch,
    };
  }
}
