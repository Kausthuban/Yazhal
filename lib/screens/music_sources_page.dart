import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/screens/extension_search_page.dart';
import 'package:yazhal/screens/extension_settings_page.dart';
import 'package:yazhal/screens/flac_extensions_page.dart';
import 'package:yazhal/screens/source_help_page.dart';
import 'package:yazhal/screens/source_repositories_page.dart';
import 'package:yazhal/services/common_services.dart' show lastFetchedLyrics;
import 'package:yazhal/services/extensions/native_extension_service.dart';
import 'package:yazhal/services/lyrics_manager.dart';
import 'package:yazhal/services/provider_router.dart';
import 'package:yazhal/services/source_repository_service.dart';
import 'package:yazhal/widgets/fast_scroll.dart';
import 'package:yazhal/widgets/mini_player_bottom_space.dart';

class MusicSourcesPage extends StatefulWidget {
  const MusicSourcesPage({super.key});
  @override
  State<MusicSourcesPage> createState() => _MusicSourcesPageState();
}

class _MusicSourcesPageState extends State<MusicSourcesPage> {
  String? message;
  Future<void> open(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (mounted) setState(() {});
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => message = null);
    } catch (error) {
      if (mounted)
        setState(
          () => message = 'Could not update this extension. Check package access and secure storage.',
        );
    }
  }

  List<Map> get lyricsProviders => NativeExtensionService.enabled
      .where(
        (p) => ((p['manifest'] as Map?)?['type'] as List? ?? []).contains(
          'lyrics_provider',
        ),
      )
      .toList();
  String get selectedLyrics {
    final value = Hive.box('settings')
        .get('lyricsExtension', defaultValue: 'automatic')
        .toString();
    return {
          'automatic',
          'builtin',
          ...lyricsProviders.map((p) => p['id'].toString()),
        }.contains(value)
        ? value
        : 'automatic';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Music sources'),
      actions: const [SourceHelpButton()],
    ),
    body: FastScroll(
      builder: (controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: Hive.box('settings')
                  .get('discoveryLanguage', defaultValue: 'automatic')
                  .toString(),
              decoration: const InputDecoration(
                labelText: 'Recommendations language',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'automatic',
                  child: Text('Learn from recent listening'),
                ),
                DropdownMenuItem(value: 'tamil', child: Text('Tamil')),
                DropdownMenuItem(value: 'english', child: Text('English')),
                DropdownMenuItem(value: 'hindi', child: Text('Hindi')),
                DropdownMenuItem(value: 'telugu', child: Text('Telugu')),
                DropdownMenuItem(value: 'malayalam', child: Text('Malayalam')),
                DropdownMenuItem(value: 'kannada', child: Text('Kannada')),
              ],
              onChanged: (v) async {
                if (v == null) return;
                await Hive.box('settings').put('discoveryLanguage', v);
                ProviderRouter.changes.value++;
                if (mounted) setState(() {});
              },
            ),
          ),
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.travel_explore,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your music, your sources',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Install a provider, review its permissions and choose where to search. Each provider declares its own audio qualities and metadata capabilities.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => open(const ExtensionSearchPage()),
                    icon: const Icon(Icons.search),
                    label: const Text('Search extensions'),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.source_outlined),
            title: const Text('Extension repositories'),
            subtitle: const Text('Browse and install verified .sflx packages'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(const SourceRepositoriesPage()),
          ),
          OutlinedButton.icon(
            onPressed: () => run(() async {
              await SourceRepositoryService.save(recommendedExtensionRegistry);
              if (mounted) await open(const SourceRepositoriesPage());
            }),
            icon: const Icon(Icons.add_link),
            label: const Text('Add SpotiFLAC / Mornye registry'),
          ),
          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: const Text('Declarative FLAC catalogs'),
            subtitle: const Text('Existing catalogs and Live Music Archive'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(const FlacExtensionsPage()),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey(
              NativeExtensionService.enabled.map((p) => p['id']).join(','),
            ),
            initialValue: selectedLyrics,
            decoration: const InputDecoration(
              labelText: 'Lyrics source',
              prefixIcon: Icon(Icons.lyrics_outlined),
            ),
            items: [
              const DropdownMenuItem(
                value: 'automatic',
                child: Text(
                  'Extensions, then built-in lyrics',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const DropdownMenuItem(
                value: 'builtin',
                child: Text('Built-in lyrics only'),
              ),
              for (final p in NativeExtensionService.enabled.where(
                (p) => ((p['manifest'] as Map?)?['type'] as List? ?? [])
                    .contains('lyrics_provider'),
              ))
                DropdownMenuItem(
                  value: p['id'].toString(),
                  child: Text(p['name'].toString()),
                ),
            ],
            onChanged: (value) async {
              await Hive.box('settings').put('lyricsExtension', value);
              LyricsManager.clearCache();
              lastFetchedLyrics = null;
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Installed extensions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (NativeExtensionService.installed.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No JavaScript extensions installed. Add the recommended registry, browse its packages and review one to install.',
              ),
            ),
          if (message != null) Text(message!),
          for (final provider in NativeExtensionService.installed)
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(provider['name'].toString()),
                    subtitle: Text(
                      '${provider['version']} · ${((provider['manifest'] as Map?)?['type'] as List? ?? []).join(' · ')}\n${provider['author']}',
                    ),
                    value: provider['enabled'] == true,
                    onChanged: (v) => run(
                      () => NativeExtensionService.enable(
                        provider['id'].toString(),
                        v,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () => open(
                            ExtensionSettingsPage(
                              id: provider['id'].toString(),
                            ),
                          ),
                          icon: const Icon(Icons.tune),
                          label: const Text('Configure'),
                        ),
                        TextButton.icon(
                          onPressed: provider['enabled'] == true
                              ? () => open(
                                  ExtensionSearchPage(
                                    initialProvider: provider['id'].toString(),
                                  ),
                                )
                              : null,
                          icon: const Icon(Icons.search),
                          label: const Text('Search'),
                        ),
                        TextButton.icon(
                          onPressed: () => run(
                            () => NativeExtensionService.instance.uninstall(
                              provider['id'].toString(),
                            ),
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Uninstall'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Text(
              'Extensions run code and can send search terms and configured credentials to their declared hosts. Enable only authors you trust. Account-gated features still require your own valid account. Not every Mornye SDK capability is implemented; unsupported encrypted/file/browser-auth operations fail explicitly.',
            ),
          ),
          const MiniPlayerBottomSpace(),
        ],
      ),
    ),
  );
}
