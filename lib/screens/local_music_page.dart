import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/extensions/l10n.dart';
import 'package:yazhal/services/common_services.dart' show userOfflineSongs;
import 'package:yazhal/services/local_music_import_service.dart';
import 'package:yazhal/services/music_folder_service.dart';
import 'package:yazhal/services/music_storage_service.dart';
import 'package:yazhal/services/offline_metadata_service.dart';
import 'package:yazhal/services/offline_taste_service.dart';
import 'package:yazhal/widgets/fast_scroll.dart';
import 'package:yazhal/widgets/offline_metadata_dialog.dart';

class LocalMusicPage extends StatefulWidget {
  const LocalMusicPage({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<LocalMusicPage> createState() => _LocalMusicPageState();
}

class _LocalMusicPageState extends State<LocalMusicPage> {
  final _originalRoot = TextEditingController();
  bool _busy = false;
  LocalImportPreview? _preview;
  String? _previewFolder;
  String? _message;

  @override
  void dispose() {
    _originalRoot.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _message = null;
      _preview = null;
      _previewFolder = null;
    });
    try {
      final folder = await MusicStorageService.pickFolder();
      if (folder == null) return;
      await MusicFolderService.add(
        folder,
        originalRoot: _originalRoot.text.trim(),
      );
      final preview = await LocalMusicImportService.preview(
        folder,
        originalRoot: _originalRoot.text.trim(),
      );
      if (mounted)
        setState(() {
          _preview = preview;
          _previewFolder = folder;
        });
    } catch (e) {
      if (mounted)
        setState(() => _message = '${context.l10n!.musicAccessError}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() => _busy = true);
    try {
      final result = await LocalMusicImportService.commit(preview);
      if (_previewFolder != null)
        await MusicFolderService.update(_previewFolder!, {
          'lastScan': DateTime.now().millisecondsSinceEpoch,
          'count': preview.songs.length,
          'issues': preview.issues.length,
          'error': null,
        });
      if (mounted)
        setState(() {
          _message = context.l10n!.musicImportResult(
            result.added,
            result.skipped,
            result.playlists,
          );
          _preview = null;
        });
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _destination() async {
    setState(() => _busy = true);
    try {
      final folder = await MusicStorageService.pickFolder();
      if (folder != null)
        await Hive.box('userNoBackup').put('downloadFolder', folder);
    } catch (e) {
      if (mounted) setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n!;
    final preview = _preview;
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.localMusic),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Folders'),
              Tab(text: 'Metadata'),
              Tab(text: 'Downloads'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            FastScroll(
              builder: (controller) => ListView(
                controller: controller,
                padding: const EdgeInsets.all(20),
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: MusicFolderService.changes,
                    builder: (context, _, __) => Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Automatic folder scanning'),
                          subtitle: const Text(
                            'On startup, resume and every 15 minutes while the app is open.',
                          ),
                          value: MusicFolderService.automatic,
                          onChanged: (value) async {
                            await Hive.box('settings')
                                .put('autoScanMusicFolders', value);
                            MusicFolderService.foreground(true);
                            if (mounted) setState(() {});
                          },
                        ),
                        for (final folder in MusicFolderService.folders)
                          Card(
                            child: Column(
                              children: [
                                SwitchListTile(
                                  title: Text(
                                    MusicFolderService.label(
                                      folder['uri'] as String,
                                    ),
                                  ),
                                  subtitle: Text(
                                    folder['error']?.toString() ??
                                        (folder['lastScan'] == null
                                            ? 'Not scanned yet'
                                            : "${folder['count']} tracks · ${folder['issues']} playlist issues\n${DateTime.fromMillisecondsSinceEpoch(folder['lastScan'] as int).toLocal()}"),
                                  ),
                                  value: folder['enabled'] == true,
                                  onChanged: (value) async {
                                    await MusicFolderService.update(
                                      folder['uri'] as String,
                                      {'enabled': value},
                                    );
                                  },
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () async {
                                              setState(() => _busy = true);
                                              try {
                                                await MusicFolderService.scan(
                                                  folder['uri'] as String,
                                                );
                                              } catch (_) {
                                              } finally {
                                                if (mounted)
                                                  setState(() => _busy = false);
                                              }
                                            },
                                      child: const Text('Scan now'),
                                    ),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => MusicFolderService.remove(
                                              folder['uri'] as String,
                                            ),
                                      child: const Text('Remove folder'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        if (MusicFolderService.folders.isEmpty)
                          const ListTile(
                            leading: Icon(Icons.library_music),
                            title: Text('Bring your music into Yazhal'),
                            subtitle: Text(
                              'Add a folder below. Removing a folder never deletes its files.',
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(l.localMusicHelp),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _originalRoot,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: l.playlistOriginalRoot,
                      helperText: l.playlistRootHelp,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Add & scan folder'),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        _message!,
                        key: const ValueKey('music-message'),
                      ),
                    ),
                  if (preview != null) ...[
                    Text(
                      l.musicPreview(
                        preview.songs.length,
                        preview.playlists.length,
                        preview.issues.length,
                      ),
                    ),
                    for (final playlist in preview.playlists)
                      ListTile(
                        title: Text(playlist['title'] as String),
                        subtitle: Text(
                          '${(playlist['list'] as List).length} ${l.songs}',
                        ),
                      ),
                    if (preview.issues.isNotEmpty)
                      ExpansionTile(
                        title: Text(l.unresolvedEntries),
                        children: [
                          for (final issue in preview.issues.take(100))
                            ListTile(dense: true, title: Text(issue)),
                        ],
                      ),
                    FilledButton(
                      onPressed: _busy || preview.songs.isEmpty
                          ? null
                          : _import,
                      child: Text(l.importLocalMusic),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _preview = null),
                      child: Text(l.cancel),
                    ),
                  ],
                  const SizedBox(height: 100),
                ],
              ),
            ),
            _metadataTab(),
            FastScroll(
              builder: (controller) => ListView(
                controller: controller,
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    l.downloadLocation,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    MusicStorageService.downloadFolder ?? l.appDefaultFolder,
                  ),
                  Text(l.downloadLocationHelp),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _destination,
                    icon: const Icon(Icons.folder),
                    label: Text(l.chooseDownloadFolder),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            await Hive.box('userNoBackup')
                                .delete('downloadFolder');
                            if (mounted) setState(() {});
                          },
                    child: Text(l.useDefaultFolder),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metadataTab() => ValueListenableBuilder<List>(
    valueListenable: userOfflineSongs,
    builder: (context, songs, _) {
      final tracks = songs.whereType<Map>().toList();
      return FastScroll(
        builder: (controller) => CustomScrollView(
          controller: controller,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverList.list(
                children: [
                  SwitchListTile(
                    title: const Text('Online metadata & artwork'),
                    subtitle: const Text(
                      'Search MusicBrainz and Cover Art Archive using song title and artist. No audio files are uploaded. Choose and confirm each match.',
                    ),
                    value: OfflineMetadataService.enabled,
                    onChanged: (value) async {
                      await Hive.box('settings')
                          .put('onlineOfflineMetadata', value);
                      if (mounted) setState(() {});
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Learn from offline listening'),
                    subtitle: const Text(
                      'Use your library and offline plays for suggestions. Online discovery uses up to three artist searches when online recommendations are enabled.',
                    ),
                    value: OfflineTasteService.enabled,
                    onChanged: (value) async {
                      await Hive.box('settings')
                          .put('offlineTasteEnabled', value);
                      OfflineTasteService.changes.value++;
                      if (mounted) setState(() {});
                    },
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await OfflineTasteService.clear();
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Offline listening history cleared'),
                          ),
                        );
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('Clear offline listening history'),
                  ),
                  const Divider(),
                  const Text(
                    'Offline songs',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'Embedded artwork is read during folder scanning. Tap a song to search for additional metadata and cover art.',
                  ),

                  if (tracks.isEmpty)
                    const ListTile(
                      title: Text('No offline songs yet'),
                      subtitle: Text(
                        'Import a folder or download a song first.',
                      ),
                    ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.builder(
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final song = tracks[index];
                  return ListTile(
                    leading: const Icon(Icons.manage_search),
                    title: Text(song['title']?.toString() ?? ''),
                    subtitle: Text(
                      '${song['artist'] ?? ''}${song['metadataSource'] == null ? '' : ' · MusicBrainz'}',
                    ),
                    onTap: () => showOfflineMetadata(context, song),
                  );
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      );
    },
  );
}
