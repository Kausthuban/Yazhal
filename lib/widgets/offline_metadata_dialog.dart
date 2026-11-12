import 'package:material_ui/material_ui.dart';
import 'package:yazhal/services/offline_metadata_service.dart';
import 'package:yazhal/services/settings_manager.dart' show offlineMode;
import 'package:yazhal/widgets/fast_scroll.dart';

Future<void> showOfflineMetadata(BuildContext context, Map song) async {
  if (offlineMode.value || !OfflineMetadataService.enabled) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Enable online metadata in Settings → Local music → Metadata, and turn off offline mode.',
        ),
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => _MetadataDialog(song: song),
  );
}

class _MetadataDialog extends StatefulWidget {
  const _MetadataDialog({required this.song});
  final Map song;
  @override
  State<_MetadataDialog> createState() => _MetadataDialogState();
}

class _MetadataDialogState extends State<_MetadataDialog> {
  late Future<List<MetadataCandidate>> _result = OfflineMetadataService.instance
      .search(widget.song);
  late final _query = TextEditingController(
    text: [
      widget.song['artist'],
      widget.song['title'],
    ].where((s) => s != null && s.toString().isNotEmpty).join(' - '),
  );
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    if (_saving ||
        _query.text.trim().isEmpty ||
        offlineMode.value ||
        !OfflineMetadataService.enabled)
      return;
    setState(() {
      _error = null;
      _result = OfflineMetadataService.instance.search({
        'title': _query.text.trim(),
      });
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Match song metadata'),
    content: SizedBox(
      width: 480,
      height: 420,
      child: Column(
        children: [
          TextField(
            controller: _query,
            enabled: !_saving,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: 'Artist - title',
              suffixIcon: IconButton(
                tooltip: 'Search metadata',
                onPressed: _saving ? null : _search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _saving
                ? const Center(child: CircularProgressIndicator())
                : FutureBuilder<List<MetadataCandidate>>(
                    future: _result,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done)
                        return const Center(child: CircularProgressIndicator());
                      if (snapshot.hasError)
                        return const Text(
                          'Metadata search unavailable. Check your connection and try again later.',
                        );
                      final matches = snapshot.data ?? [];
                      return FastScroll(
                        builder: (controller) => ListView(
                          controller: controller,
                          children: [
                            const Text(
                              'MusicBrainz / Cover Art Archive\nChoose a match to apply. Original audio files stay untouched; artwork availability varies.',
                            ),
                            if (_error != null) Text(_error!),
                            if (matches.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'No matches. Adjust the artist or title above to try again.',
                                ),
                              ),
                            for (final match in matches)
                              ListTile(
                                title: Text(match.title),
                                subtitle: Text(
                                  '${match.artist}\n${match.album.isEmpty ? 'Album unknown' : match.album}',
                                ),
                                isThreeLine: true,
                                trailing: const Icon(
                                  Icons.check_circle_outline,
                                ),
                                onTap: () async {
                                  setState(() => _saving = true);
                                  try {
                                    if (offlineMode.value ||
                                        !OfflineMetadataService.enabled)
                                      throw StateError(
                                        'Online lookup is disabled',
                                      );
                                    final result = await OfflineMetadataService
                                        .instance
                                        .apply(
                                          widget.song['ytid'].toString(),
                                          match,
                                        );
                                    if (context.mounted) {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      Navigator.pop(context);
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            result.artwork
                                                ? 'Metadata and artwork saved'
                                                : 'Metadata saved. No artwork available for this release.',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (_) {
                                    if (mounted)
                                      setState(() {
                                        _saving = false;
                                        _error = 'Could not save this match. Check the metadata setting and try again.';
                                      });
                                  }
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
