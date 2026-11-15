import 'package:material_ui/material_ui.dart';
import 'package:yazhal/services/extensions/native_extension_service.dart';

/// Metadata providers and audio providers are separate. The user confirms the
/// exact recording when crossing sources; matching is never silently guessed.
Future<Map<String, dynamic>?> chooseAudioSourceTrack(
  BuildContext context,
  Map original,
) async {
  final providers = NativeExtensionService.enabled
      .where(
        (p) => ((p['manifest'] as Map?)?['type'] as List? ?? []).contains(
          'download_provider',
        ),
      )
      .toList();
  if (providers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enable a download extension in Music sources first.'),
      ),
    );
    return null;
  }
  final selected = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Choose an audio source',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text(
            'This result supplies metadata. Select an audio provider, then confirm the matching recording.',
          ),
          for (final provider in providers)
            ListTile(
              leading: const Icon(Icons.library_music_outlined),
              title: Text(provider['name'].toString()),
              onTap: () => Navigator.pop(context, provider['id'].toString()),
            ),
        ],
      ),
    ),
  );
  if (selected == null || !context.mounted) return null;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _RecordingPicker(provider: selected, original: original),
  );
}

class _RecordingPicker extends StatefulWidget {
  const _RecordingPicker({required this.provider, required this.original});
  final String provider;
  final Map original;
  @override
  State<_RecordingPicker> createState() => _RecordingPickerState();
}

class _RecordingPickerState extends State<_RecordingPicker> {
  late final TextEditingController query = TextEditingController(
    text: '${widget.original['title'] ?? ''} ${widget.original['artist'] ?? ''}'
        .trim(),
  );
  late Future<List<Map<String, dynamic>>> result = NativeExtensionService
      .instance
      .search(widget.provider, query.text);
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Confirm the recording'),
    content: SizedBox(
      width: 480,
      height: 420,
      child: Column(
        children: [
          TextField(
            controller: query,
            onSubmitted: (_) => setState(
              () => result = NativeExtensionService.instance.search(
                widget.provider,
                query.text,
              ),
            ),
            decoration: InputDecoration(
              labelText: 'Title and artist',
              suffixIcon: IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search),
                onPressed: () => setState(
                  () => result = NativeExtensionService.instance.search(
                    widget.provider,
                    query.text,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: result,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done)
                  return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError)
                  return const Center(
                    child: Text(
                      'Search failed. Check the audio provider’s settings and network.',
                    ),
                  );
                final tracks = snapshot.data ?? [];
                if (tracks.isEmpty)
                  return const Center(
                    child: Text(
                      'No recordings found. Try another query or source.',
                    ),
                  );
                return ListView(
                  children: [
                    for (final track in tracks)
                      ListTile(
                        title: Text(track['title'].toString()),
                        subtitle: Text(
                          '${track['artist']} · ${track['album']}\n${track['duration'] ?? '?'} seconds',
                        ),
                        onTap: () => Navigator.pop(context, track),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
