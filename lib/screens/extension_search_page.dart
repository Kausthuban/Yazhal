import 'package:material_ui/material_ui.dart';
import 'package:yazhal/screens/music_sources_page.dart';
import 'package:yazhal/screens/search_page.dart';
import 'package:yazhal/screens/source_diagnostics_page.dart';
import 'package:yazhal/screens/source_help_page.dart';
import 'package:yazhal/screens/track_information_page.dart';
import 'package:yazhal/services/provider_router.dart';
import 'package:yazhal/services/settings_manager.dart' show offlineMode;
import 'package:yazhal/widgets/fast_scroll.dart';
import 'package:yazhal/widgets/mini_player_bottom_space.dart';
import 'package:yazhal/widgets/song_bar.dart';
import 'package:yazhal/widgets/song_selection_region.dart';

class ExtensionSearchPage extends StatefulWidget {
  const ExtensionSearchPage({
    this.initialProvider,
    this.searchProvider,
    this.selectProvider,
    super.key,
  });
  final String? initialProvider;
  final Future<void> Function(String)? selectProvider;
  final Future<List<Map<String, dynamic>>> Function(String, String)?
  searchProvider;
  @override
  State<ExtensionSearchPage> createState() => _ExtensionSearchPageState();
}

class _ExtensionSearchPageState extends State<ExtensionSearchPage> {
  final query = TextEditingController();
  String? selected, message;
  List<Map<String, dynamic>> songs = [];
  bool busy = false, failed = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    selected = widget.initialProvider ?? ProviderRouter.selected;
  }

  @override
  void dispose() {
    generation++;
    query.dispose();
    super.dispose();
  }

  String get providerName =>
      ProviderRouter.available
          .where((p) => p['id'] == selected)
          .firstOrNull?['name']
          ?.toString() ??
      'Music source';

  Future<void> search() async {
    if (busy || selected == null || query.text.trim().isEmpty) return;
    if (offlineMode.value) {
      setState(() {
        failed = false;
        message =
            'Offline mode is on. Turn it off in Settings to search online.';
      });
      return;
    }
    final token = ++generation, id = selected!, name = providerName;
    final terms = query.text.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      failed = false;
      message = null;
      songs = [];
    });
    try {
      final rows = await (widget.searchProvider ?? ProviderRouter.searchFrom)(
        id,
        terms,
      );
      if (!mounted || generation != token) return;
      setState(() {
        songs = rows;
        message = rows.isEmpty
            ? 'No songs found on $name. Try another search or provider.'
            : '${rows.length} songs · $name';
      });
    } catch (error) {
      if (!mounted || generation != token) return;
      setState(() {
        failed = true;
        message = ProviderRouter.searchProblem(error, name);
      });
    } finally {
      if (mounted && generation == token) setState(() => busy = false);
    }
  }

  Future<void> manageSources() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const MusicSourcesPage()),
    );
    if (!mounted) return;
    setState(() {
      selected = ProviderRouter.selected;
      generation++;
      busy = false;
      songs = [];
      message = null;
      failed = false;
    });
  }

  Future<void> chooseProvider() async {
    FocusScope.of(context).unfocus();
    final providers = ProviderRouter.available;
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a music provider',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Providers have different catalogues and availability.',
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final provider in providers)
                      ListTile(
                        leading: Icon(
                          provider['kind'] == 'catalog'
                              ? Icons.graphic_eq
                              : Icons.extension_outlined,
                        ),
                        title: Text(provider['name'].toString()),
                        subtitle: Text(
                          [
                            provider['description']?.toString() ??
                                ((((provider['manifest'] as Map?)?['type']
                                                as List? ??
                                            [])
                                        .contains('download_provider'))
                                    ? 'Search and audio downloads'
                                    : 'Metadata only · choose an audio source to play'),
                            if (provider['enabled'] != true)
                              'Select to enable and use',
                          ].join('\n'),
                        ),
                        trailing: provider['id'] == selected
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () =>
                            Navigator.pop(context, provider['id'].toString()),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(context, '__manage'),
                icon: const Icon(Icons.add),
                label: const Text('Add or manage sources'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || id == null) return;
    if (id == '__manage') {
      await manageSources();
      return;
    }
    // Invalidate the old request before an asynchronous enable/persist operation.
    generation++;
    setState(() {
      busy = false;
      songs = [];
      message = null;
      failed = false;
    });
    try {
      await (widget.selectProvider ?? ProviderRouter.select)(id);
      if (!mounted) return;
      setState(() => selected = id);
      if (query.text.trim().isNotEmpty) await search();
    } catch (_) {
      if (mounted)
        setState(() {
          failed = true;
          message = 'Could not enable this provider. Add or configure a source in Settings.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ProviderRouter.searchable.any((p) => p['id'] == selected))
      selected = ProviderRouter.selected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
          const SourceHelpButton(),
          IconButton(
            tooltip: 'Manage music sources',
            onPressed: manageSources,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: SongSelectionRegion(
        songs: songs,
        filter: '${selected ?? ""}:${query.text}',
        child: FastScroll(
          builder: (controller) => ListView.builder(
            controller: controller,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: songs.length + 2,
            itemBuilder: (context, index) {
              if (index == songs.length + 1)
                return const MiniPlayerBottomSpace();
              if (index == 0)
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const Key('online-search-field'),
                      controller: query,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => search(),
                      onChanged: (_) {
                        generation++;
                        setState(() {
                          busy = false;
                          message = null;
                          failed = false;
                          songs = [];
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search songs or artists',
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHigh,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(32),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(32),
                          borderSide: BorderSide.none,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 60,
                          minHeight: 52,
                        ),
                        prefixIcon: IconButton(
                          key: const Key('search-provider-button'),
                          tooltip: 'Change provider · $providerName',
                          onPressed: chooseProvider,
                          icon: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.library_music_outlined, size: 20),
                              Icon(Icons.arrow_drop_down, size: 16),
                            ],
                          ),
                        ),
                        suffixIcon: IconButton(
                          tooltip: 'Search music',
                          onPressed: busy || selected == null ? null : search,
                          icon: const Icon(Icons.search),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      child: Text(
                        selected == null
                            ? 'Choose a provider to search online'
                            : 'Searching $providerName',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (selected == ProviderRouter.youtubeId)
                      TextButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const SearchPage(classic: true),
                          ),
                        ),
                        icon: const Icon(Icons.manage_search),
                        label: const Text('Classic Musify search'),
                      ),
                    if (selected == 'jiosaavn' && !failed)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const SourceDiagnosticsPage(),
                            ),
                          ),
                          icon: const Icon(Icons.network_check),
                          label: const Text('Check source'),
                        ),
                      ),
                    if (busy) const LinearProgressIndicator(),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: failed
                            ? Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .errorContainer,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(message!),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: search,
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('Retry'),
                                        ),
                                        TextButton(
                                          onPressed: chooseProvider,
                                          child: const Text('Change provider'),
                                        ),
                                        if (selected == 'jiosaavn')
                                          TextButton.icon(
                                            onPressed: () => Navigator.push(
                                              context,
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    const SourceDiagnosticsPage(),
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.network_check,
                                            ),
                                            label: const Text('Check source'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              )
                            : Text(message!),
                      ),
                    if (!busy &&
                        !failed &&
                        songs.isEmpty &&
                        message != null &&
                        !offlineMode.value)
                      TextButton(
                        onPressed: chooseProvider,
                        child: const Text('Choose another provider'),
                      ),
                  ],
                );
              final song = songs[index - 1];
              final provider = ProviderRouter.available
                  .where((p) => p['id'] == song['extensionId'])
                  .firstOrNull;
              final metadataOnly =
                  song['source'] == 'js-extension' &&
                  !((provider?['manifest'] as Map?)?['type'] as List? ?? [])
                      .contains('download_provider');
              return SongBar(
                song,
                false,
                key: ValueKey(song['ytid']),
                onPlay: metadataOnly
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => TrackInformationPage(song: song),
                        ),
                      )
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }
}
