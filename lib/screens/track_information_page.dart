import 'package:material_ui/material_ui.dart';
import 'package:yazhal/services/common_services.dart';
import 'package:yazhal/services/extensions/native_extension_service.dart';
import 'package:yazhal/services/lyrics_manager.dart';
import 'package:yazhal/services/music_storage_service.dart';
import 'package:yazhal/services/settings_manager.dart' show offlineMode;
import 'package:yazhal/widgets/fast_scroll.dart';
import 'package:yazhal/widgets/mini_player_bottom_space.dart';

class TrackInformationPage extends StatefulWidget {
  const TrackInformationPage({required this.song, super.key});
  final Map song;
  @override
  State<TrackInformationPage> createState() => _TrackInformationPageState();
}

class _TrackInformationPageState extends State<TrackInformationPage> {
  late Map song = Map.of(widget.song);
  bool busy = false;
  String? message, lyrics;
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted)
        setState(
          () => message = 'This provider could not return more information. Check its settings and capabilities.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> enrich() async {
    if (!isNativeExtensionTrack(song) || offlineMode.value) return;
    final raw = await NativeExtensionService.instance.call(
      song['extensionId'].toString(),
      'getTrack',
      [song['providerTrackId']],
    );
    if (raw is! Map) throw StateError('No track metadata');
    final metadata = NativeExtensionService.normalizeTrack(
      song['extensionId'].toString(),
      raw,
    );
    if (metadata['providerTrackId'] != song['providerTrackId'])
      throw StateError('Provider returned another recording');
    if (mounted) setState(() => song = {...song, ...metadata});
  }

  @override
  Widget build(BuildContext context) {
    final details = <String, dynamic>{
      'Title': song['title'],
      'Artist': song['artist'],
      'Album': song['album'],
      'Source': song['extensionId'] ?? song['source'] ?? 'YouTube',
      'Duration (seconds)': song['duration'],
      'ISRC': song['isrc'],
      'Codec': song['audioCodec'],
      'Bitrate (kbps)': song['audioBitrateKbps'],
      'Download quality':
          song['actualDownloadQuality'] ?? song['downloadQuality'],
      'Year': song['year'],
      'Genre': song['genre'],
      'Track number': song['trackNumber'],
      'Disc number': song['discNumber'],
      'Album artist': song['albumArtist'],
      'Composer': song['composer'],
    };
    final raw = song['providerTrack'] as Map? ?? {};
    for (final key in [
      'release_date',
      'release_year',
      'label',
      'copyright',
      'barcode',
      'genres',
      'credits',
      'track_number',
      'disc_number',
      'album_artist',
      'isrc',
    ]) {
      if (raw[key] != null) details[key.replaceAll('_', ' ')] = raw[key];
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Track information')),
      body: FastScroll(
        builder: (controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              song['title']?.toString() ?? 'Track',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(song['artist']?.toString() ?? ''),
            if (busy) const LinearProgressIndicator(),
            if (message != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(message!)),
            for (final entry in details.entries)
              if (entry.value != null && entry.value.toString().isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.key),
                  subtitle: SelectableText(entry.value.toString()),
                ),
            if (isNativeExtensionTrack(song))
              OutlinedButton.icon(
                onPressed: busy || offlineMode.value ? null : () => run(enrich),
                icon: const Icon(Icons.manage_search),
                label: const Text('Fetch full source metadata'),
              ),
            if (getOfflineSongByYtid(song['ytid']).isNotEmpty)
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        await MusicStorageService.mutateOfflineSongs(
                          (current) => current
                              .map(
                                (entry) => entry['ytid'] == song['ytid']
                                    ? {
                                        ...entry,
                                        for (final key in [
                                          'title',
                                          'artist',
                                          'album',
                                          'isrc',
                                          'genre',
                                          'year',
                                        ])
                                          if (song[key] != null) key: song[key],
                                      }
                                    : entry,
                              )
                              .toList(),
                          onSaved: (next) => userOfflineSongs.value = next,
                        );
                        if (mounted)
                          setState(
                            () => message = 'Library metadata saved. The original audio file was not rewritten.',
                          );
                      }),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save metadata to library'),
              ),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => run(() async {
                      final result = await LyricsManager().fetchLyricsResult(
                        TrackInfo(
                          title: song['title']?.toString() ?? '',
                          artist: song['artist']?.toString() ?? '',
                          album: song['album']?.toString(),
                        ),
                      );
                      if (mounted)
                        setState(
                          () => lyrics = result == null
                              ? 'No lyrics found.'
                              : '${result.text}\n\nSource: ${result.source}',
                        );
                    }),
              icon: const Icon(Icons.lyrics_outlined),
              label: const Text('Find lyrics'),
            ),
            if (lyrics != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: SelectableText(lyrics!),
              ),
            const MiniPlayerBottomSpace(),
          ],
        ),
      ),
    );
  }
}
