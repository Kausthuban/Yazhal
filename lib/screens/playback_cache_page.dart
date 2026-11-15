import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/services/playback_cache.dart';
import 'package:yazhal/widgets/mini_player_bottom_space.dart';

class PlaybackCachePage extends StatefulWidget {
  const PlaybackCachePage({super.key});
  @override
  State<PlaybackCachePage> createState() => _PlaybackCachePageState();
}

class _PlaybackCachePageState extends State<PlaybackCachePage> {
  late Future<int> usage = PlaybackCache.instance.bytes();
  bool busy = false;
  String? message;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Playback buffer')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SwitchListTile(
          title: const Text('Full-song temporary buffer'),
          subtitle: const Text(
            'Start playing promptly while the track fills on disk in chunks. Current and next track share one transfer each. Data saver limits speculative transfers.',
          ),
          value: PlaybackCache.enabled,
          onChanged: (value) async {
            await Hive.box('settings').put('playbackCacheEnabled', value);
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: (Hive.box(
            'settings',
          ).get('playbackCacheMiB', defaultValue: 512) as num).toInt(),
          decoration: const InputDecoration(
            labelText: 'Storage budget',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final size in [128, 256, 512, 1024])
              DropdownMenuItem(value: size, child: Text('$size MiB')),
          ],
          onChanged: (size) async {
            if (size == null) return;
            await Hive.box('settings').put('playbackCacheMiB', size);
            await PlaybackCache.instance.trim();
            if (mounted) setState(() => usage = PlaybackCache.instance.bytes());
          },
        ),
        const SizedBox(height: 16),
        FutureBuilder<int>(
          future: usage,
          builder: (_, snapshot) => Text(
            'Cached audio: ${((snapshot.data ?? 0) / 1048576).toStringAsFixed(1)} MiB',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear temporary audio'),
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    await PlaybackCache.instance.clear();
                    if (mounted)
                      setState(() {
                        usage = PlaybackCache.instance.bytes();
                        message = 'Temporary audio cleared. The current track buffer is retained until it changes. Downloads were not deleted.';
                      });
                  } catch (_) {
                    if (mounted)
                      setState(
                        () => message = 'Could not clear the buffer. Try again when playback is paused.',
                      );
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(message!),
          ),
        const SizedBox(height: 16),
        const Text(
          'Playback starts as soon as the decoder has enough audio (Android startup target: 500 ms), then builds 20 seconds of headroom while the full track keeps loading. Next-track preloading waits for 5 seconds of buffered audio and enough bandwidth. Actual startup depends on the source, connection and audio format.',
        ),
        const MiniPlayerBottomSpace(),
      ],
    ),
  );
}
