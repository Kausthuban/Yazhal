import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:yazhal/services/local_music_import_service.dart';

/// Scans only while foregrounded; unavailable files are never auto-deleted.
class MusicFolderService {
  static final changes = ValueNotifier<int>(0);
  static Timer? _timer;
  static Future<void>? _running;
  static List<Map<String, dynamic>> get folders =>
      (Hive.box('userNoBackup').get(
        'musicFolders',
        defaultValue: <dynamic>[],
      ) as List).whereType<Map>().map(Map<String, dynamic>.from).toList();
  static bool get automatic =>
      Hive.box('settings').get('autoScanMusicFolders', defaultValue: false) ==
      true;
  static Future<void> save(List<Map<String, dynamic>> list) async {
    await Hive.box('userNoBackup').put('musicFolders', list);
    changes.value++;
  }

  static Future<void> add(String uri, {String? originalRoot}) async {
    final list = folders;
    if (!list.any((f) => f['uri'] == uri)) {
      list.add({
        'uri': uri,
        'enabled': true,
        'originalRoot': originalRoot ?? '',
      });
      await save(list);
    } else {
      await update(uri, {
        'error': null,
        if (originalRoot != null) 'originalRoot': originalRoot,
      });
    }
  }

  static Future<void> update(String uri, Map<String, dynamic> values) async {
    await save(
      folders.map((f) => f['uri'] == uri ? {...f, ...values} : f).toList(),
    );
  }

  static Future<void> remove(String uri) =>
      save(folders..removeWhere((f) => f['uri'] == uri));
  static String label(String uri) {
    final parsed = Uri.tryParse(uri);
    final decoded = parsed == null ? uri : Uri.decodeComponent(parsed.path);
    return decoded.split('/').where((p) => p.isNotEmpty).lastOrNull ?? uri;
  }

  static void foreground(bool active) {
    _timer?.cancel();
    _timer = null;
    if (!active) return;
    unawaited(scanAutomatic());
    _timer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(scanAutomatic()),
    );
  }

  static Future<void> scanAutomatic() {
    if (!automatic) return Future.value();
    return _running ??= _scanAutomatic().whenComplete(() {
      _running = null;
    });
  }

  static Future<void> _scanAutomatic() async {
    for (final folder in folders) {
      if (!automatic) break;
      final last = (folder['lastScan'] as num?)?.toInt() ?? 0;
      if (folder['enabled'] == true &&
          DateTime.now().millisecondsSinceEpoch - last >=
              const Duration(minutes: 15).inMilliseconds) {
        try {
          await scan(folder['uri'] as String);
        } catch (_) {
          /* Status saved per folder; continue others. */
        }
      }
    }
  }

  static Future<void> scan(String uri) async {
    final folder = folders.where((f) => f['uri'] == uri).firstOrNull;
    if (folder == null) return;
    try {
      final preview = await LocalMusicImportService.preview(
        uri,
        originalRoot: folder['originalRoot'] as String?,
      );
      await LocalMusicImportService.commit(preview);
      await update(uri, {
        'lastScan': DateTime.now().millisecondsSinceEpoch,
        'count': preview.songs.length,
        'issues': preview.issues.length,
        'error': null,
      });
    } catch (_) {
      await update(uri, {
        'error': 'Folder unavailable. Select it again to restore access.',
      });
      rethrow;
    }
  }
}
