import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/screens/source_repositories_page.dart';
import 'package:yazhal/services/flac_extension_service.dart';
import 'package:yazhal/services/settings_manager.dart' show offlineMode;
import 'package:yazhal/widgets/fast_scroll.dart';
import 'package:yazhal/widgets/mini_player_bottom_space.dart';
import 'package:yazhal/widgets/song_bar.dart';
import 'package:yazhal/widgets/song_selection_region.dart';

class FlacExtensionsPage extends StatefulWidget {
  const FlacExtensionsPage({super.key});
  @override
  State<FlacExtensionsPage> createState() => _FlacExtensionsPageState();
}

class _FlacExtensionsPageState extends State<FlacExtensionsPage> {
  String? _message;
  Future<void> _install() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      if ((file.lengthSync() ?? 0) > 65536)
        throw const FormatException('Manifest exceeds 64 KiB');
      final bytes = <int>[];
      await for (final chunk in file.readAsByteStream().timeout(
        const Duration(seconds: 20),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 65536)
          throw const FormatException('Manifest exceeds 64 KiB');
      }
      if (bytes.length > 65536)
        throw const FormatException(
          'Manifest must be a JSON file smaller than 64 KiB',
        );
      final extension = FlacExtension.parse(
        jsonDecode(utf8.decode(bytes)) as Map,
      );
      await FlacExtensionService.install(extension);
      if (mounted)
        setState(
          () => _message =
              '${extension.name} installed. Review its hosts before enabling.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _message = 'Could not install. Check the extension JSON format and HTTPS hosts.',
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Music sources & extensions')),
    body: FastScroll(
      builder: (controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Optional lossless discovery',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Enable a source to search for actual FLAC files. The built-in catalog covers live recordings. Availability depends on each source; standard search remains available.',
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const SourceRepositoriesPage(),
              ),
            ),
            icon: const Icon(Icons.source),
            label: const Text('Source repositories'),
          ),
          FilledButton.icon(
            onPressed: _install,
            icon: const Icon(Icons.extension),
            label: const Text('Install catalog extension (.json)'),
          ),
          if (_message != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
          for (final extension in FlacExtensionService.extensions)
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(extension.name),
                    subtitle: Text(extension.hosts.join(', ')),
                    value: extension.enabled,
                    onChanged: (value) async {
                      await FlacExtensionService.enable(extension, value);
                      if (mounted) setState(() {});
                    },
                  ),
                  if (!extension.builtIn)
                    TextButton.icon(
                      onPressed: () async {
                        await FlacExtensionService.remove(extension.id);
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Uninstall'),
                    ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const FlacSearchPage()),
            ),
            icon: const Icon(Icons.search),
            label: const Text('Search FLAC catalog'),
          ),
          const Text(
            'Extensions declare a catalog URL and audio hosts; they cannot run scripts. Search text is sent only to sources you enable. Downloaded files remain playable when a source is disabled.',
          ),
          const MiniPlayerBottomSpace(),
        ],
      ),
    ),
  );
}

class FlacSearchPage extends StatefulWidget {
  const FlacSearchPage({super.key});
  @override
  State<FlacSearchPage> createState() => _FlacSearchPageState();
}

class _FlacSearchPageState extends State<FlacSearchPage> {
  final query = TextEditingController();
  List<Map<String, dynamic>> _songs = [];
  bool _busy = false;
  String? _status;
  String _source = Hive.box('settings')
      .get('catalogSearchSource', defaultValue: 'all')
      .toString();
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (_busy || query.text.trim().isEmpty) return;
    if (offlineMode.value) {
      setState(() => _status = 'Turn off offline mode to search FLAC sources.');
      return;
    }
    if (_source != 'all' &&
        !FlacExtensionService.extensions.any(
          (e) => e.enabled && e.id == _source,
        ))
      _source = 'all';
    final sources = FlacExtensionService.extensions
        .where((e) => e.enabled && (_source == 'all' || e.id == _source))
        .toList();
    if (sources.isEmpty) {
      setState(
        () => _status =
            'No sources enabled. Open the source manager to enable one.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
      _songs = [];
    });
    final songs = <Map<String, dynamic>>[];
    var failures = 0;
    for (final source in sources) {
      try {
        songs.addAll(
          await FlacExtensionService.instance.search(source, query.text),
        );
      } catch (_) {
        failures++;
      }
    }
    final ids = <String>{};
    if (mounted)
      setState(() {
        _songs = songs.where((s) => ids.add(s['ytid'] as String)).toList();
        _busy = false;
        _status =
            '${_songs.length} FLAC tracks${failures == 0 ? '' : ' · $failures source(s) unavailable'}';
      });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Search FLAC'),
      actions: [
        IconButton(
          tooltip: 'Manage sources',
          icon: const Icon(Icons.extension),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const FlacExtensionsPage(),
              ),
            );
            if (mounted) setState(() {});
          },
        ),
      ],
    ),
    body: SongSelectionRegion(
      songs: _songs,
      child: FastScroll(
        builder: (controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue:
                  FlacExtensionService.extensions.any(
                    (e) => e.enabled && e.id == _source,
                  )
                  ? _source
                  : 'all',
              decoration: const InputDecoration(labelText: 'Search source'),
              items: [
                const DropdownMenuItem(
                  value: 'all',
                  child: Text('All enabled catalogs'),
                ),
                ...FlacExtensionService.extensions
                    .where((e) => e.enabled)
                    .map(
                      (e) => DropdownMenuItem(value: e.id, child: Text(e.name)),
                    ),
              ],
              onChanged: _busy
                  ? null
                  : (value) async {
                      setState(() {
                        _source = value ?? 'all';
                        _songs = [];
                        _status = null;
                      });
                      await Hive.box('settings')
                          .put('catalogSearchSource', _source);
                    },
            ),
            TextField(
              controller: query,
              enabled: !_busy,
              onSubmitted: (_) => search(),
              decoration: InputDecoration(
                labelText: 'Artist or song',
                suffixIcon: IconButton(
                  tooltip: 'Search FLAC',
                  onPressed: _busy ? null : search,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Lossless files from enabled catalogs. Use each track menu to download to your selected folder.',
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_status != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_status!)),
            for (final song in _songs) SongBar(song, false),
            const MiniPlayerBottomSpace(),
          ],
        ),
      ),
    ),
  );
}
