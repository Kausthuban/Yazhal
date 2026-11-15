import 'package:material_ui/material_ui.dart';
import 'package:yazhal/services/extensions/native_extension_service.dart';
import 'package:yazhal/services/flac_extension_service.dart';
import 'package:yazhal/services/source_repository_service.dart';
import 'package:yazhal/widgets/fast_scroll.dart';
import 'package:yazhal/widgets/mini_player_bottom_space.dart';

class SourceRepositoriesPage extends StatefulWidget {
  const SourceRepositoriesPage({super.key});
  @override
  State<SourceRepositoriesPage> createState() => _SourceRepositoriesPageState();
}

class _SourceRepositoriesPageState extends State<SourceRepositoriesPage> {
  final service = SourceRepositoryService();
  final url = TextEditingController();
  List<SourceRepositoryEntry> entries = [];
  String? selected, message;
  bool busy = false;
  @override
  void dispose() {
    service.close();
    url.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted)
        setState(
          () => message = e is FormatException ? e.message : 'Repository operation failed. Check connectivity and the index URL.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> install(SourceRepositoryEntry entry) async {
    if (entry.javascript) {
      final bytes = await service.fetchExtensionPackage(entry);
      final package = await NativeExtensionService.instance.inspectPackage(
        entry.id,
        bytes,
        entry.checksum,
      );
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Install ${package.name}?'),
          content: SingleChildScrollView(
            child: Text(
              'Version ${package.version}\nAuthor: ${package.author}\n\nDeclared network hosts:\n${package.hosts.join('\n')}\n\nThis package executes JavaScript when enabled. It can use search terms and configured credentials on these hosts. Yazhal supports synchronous search, metadata, lyrics and direct audio URLs; browser login, encrypted transfers and arbitrary file APIs are not available.\n\n${package.licenses.values.first}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Install disabled'),
            ),
          ],
        ),
      );
      if (accepted == true) {
        await NativeExtensionService.instance.install(
          package,
          bytes,
          repository: selected ?? '',
          downloadUrl: entry.downloadUrl,
        );
        if (mounted)
          setState(
            () => message =
                'Installed. Open Music sources to configure and enable ${package.name}.',
          );
      }
      return;
    }
    final extension = await service.resolve(entry);
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Install ${extension.name}?'),
        content: Text(
          'This source can receive your search terms and provide audio from:\n${extension.hosts.join('\n')}\n\nA checksum verifies package integrity, not the trustworthiness of its publisher. Installed sources start disabled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await FlacExtensionService.install(extension);
      if (mounted)
        setState(
          () => message = 'Installed. Enable the source in Music sources.',
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Source repositories')),
    body: FastScroll(
      builder: (controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Add a public HTTPS registry JSON URL or a GitHub extension repository containing registry.json. Repository refresh never installs or updates code automatically.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: url,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Repository URL',
              hintText: 'https://github.com/owner/extensions',
            ),
          ),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () => run(() async {
                    await SourceRepositoryService.save(url.text);
                    url.clear();
                  }),
            icon: const Icon(Icons.add),
            label: const Text('Add repository'),
          ),
          if (busy) const LinearProgressIndicator(),
          if (message != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(message!)),
          for (final repo in SourceRepositoryService.repositories)
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(repo['url'].toString()),
                    value: repo['enabled'] == true,
                    onChanged: busy
                        ? null
                        : (value) => run(() async {
                            await SourceRepositoryService.save(
                              repo['url'].toString(),
                              enabled: value,
                            );
                            entries = [];
                            selected = null;
                          }),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: busy || repo['enabled'] != true
                            ? null
                            : () => run(() async {
                                final result = await service.refresh(repo);
                                if (!mounted) return;
                                setState(() {
                                  entries = result;
                                  selected = repo['url'].toString();
                                });
                              }),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Browse / refresh'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                await SourceRepositoryService.remove(
                                  repo['url'].toString(),
                                );
                                entries = [];
                                selected = null;
                              }),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (selected != null)
            Text(
              'Catalog entries from $selected',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          for (final entry in entries)
            ListTile(
              title: Text(entry.name),
              subtitle: Text(
                '${entry.description}\n${entry.compatible
                    ? 'Declarative catalog'
                    : entry.javascript
                    ? 'Mornye / SpotiFLAC JavaScript package · review permissions'
                    : 'Unsupported runtime: ${entry.runtime}'}',
              ),
              trailing: (entry.compatible || entry.javascript)
                  ? IconButton(
                      tooltip: 'Review and install',
                      onPressed: busy ? null : () => run(() => install(entry)),
                      icon: const Icon(Icons.download),
                    )
                  : const Icon(Icons.info_outline),
            ),
          const SizedBox(height: 16),
          const Text(
            'Repository management is inspired by Mornye. Mornye is an app, not an audio source. Its JavaScript extensions need its own runtime. Yazhal supports declarative catalogs and a bounded JavaScript SDK for search, metadata, lyrics and direct audio. Provider-specific native APIs may require additional adapters.',
          ),
          const MiniPlayerBottomSpace(),
        ],
      ),
    ),
  );
}
