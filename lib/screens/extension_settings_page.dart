import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/services/common_services.dart' show lastFetchedLyrics;
import 'package:yazhal/services/extensions/native_extension_service.dart';
import 'package:yazhal/services/lyrics_manager.dart';
import 'package:yazhal/widgets/fast_scroll.dart';

class ExtensionSettingsPage extends StatefulWidget {
  const ExtensionSettingsPage({required this.id, super.key});
  final String id;
  @override
  State<ExtensionSettingsPage> createState() => _ExtensionSettingsPageState();
}

class _ExtensionSettingsPageState extends State<ExtensionSettingsPage> {
  final controllers = <String, TextEditingController>{};
  Map<String, dynamic> values = {}, state = {};
  Map? provider;
  bool loading = true, saving = false;
  String? message;
  @override
  void initState() {
    super.initState();
    load();
  }

  List<Map> get fields =>
      ((provider?['manifest'] as Map?)?['settings'] as List? ?? [])
          .whereType<Map>()
          .where((s) => s['type'] != 'button')
          .toList();
  Future<void> load() async {
    try {
      provider = NativeExtensionService.installed
          .where((e) => e['id'] == widget.id)
          .first;
      state = await NativeExtensionService.instance.stateStore.read(widget.id);
      values = Map<String, dynamic>.from(state['settings'] as Map? ?? {});
      for (final field in fields) {
        final key = field['key'].toString();
        final value = values[key] ?? field['default'] ?? '';
        values[key] = value;
        controllers[key] = TextEditingController(text: value.toString());
      }
    } catch (_) {
      message = 'Secure storage is unavailable. Configuration was not written to plain-text storage.';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      for (final field in fields) {
        final key = field['key'].toString();
        if (field['type'] != 'boolean' && field['type'] != 'bool')
          values[key] = controllers[key]!.text;
      }
      await NativeExtensionService.instance.stateStore.write(widget.id, {
        'settings': values,
        'storage': {},
      });
      LyricsManager.clearCache();
      lastFetchedLyrics = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Extension settings saved securely.')),
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted)
        setState(
          () => message = 'Could not save to secure storage. No plain-text fallback was used.',
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(provider?['name']?.toString() ?? 'Extension settings'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : FastScroll(
            builder: (controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.all(20),
              children: [
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(message!),
                  ),
                const Text(
                  'Settings and provider tokens are encrypted by platform secure storage. Configure only accounts and servers you are authorized to use. Changing settings clears this provider’s cached session.',
                ),
                const SizedBox(height: 16),
                if (((provider?['manifest'] as Map?)?['qualityOptions']
                            as List? ??
                        [])
                    .isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Streaming quality',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: (() {
                        final options =
                            ((provider!['manifest'] as Map)['qualityOptions']
                                    as List)
                                .whereType<Map>()
                                .toList();
                        final saved = Hive.box('settings')
                            .get('streamQuality.${widget.id}');
                        return options.any((q) => q['id'] == saved)
                            ? saved.toString()
                            : options.first['id'].toString();
                      })(),
                      items: [
                        for (final q
                            in ((provider!['manifest'] as Map)['qualityOptions']
                                    as List)
                                .whereType<Map>())
                          DropdownMenuItem(
                            value: q['id'].toString(),
                            child: Text((q['label'] ?? q['id']).toString()),
                          ),
                      ],
                      onChanged: (value) =>
                          Hive.box('settings')
                              .put('streamQuality.${widget.id}', value),
                    ),
                  ),
                for (final field in fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child:
                        (field['type'] == 'boolean' || field['type'] == 'bool')
                        ? SwitchListTile(
                            title: Text(
                              (field['label'] ?? field['key']).toString(),
                            ),
                            value: values[field['key']] == true,
                            onChanged: (v) => setState(
                              () => values[field['key'].toString()] = v,
                            ),
                          )
                        : TextField(
                            controller: controllers[field['key'].toString()],
                            obscureText: RegExp(
                              'token|password|secret|cookie|key|arl|session',
                              caseSensitive: false,
                            ).hasMatch(field['key'].toString()),
                            decoration: InputDecoration(
                              labelText: (field['label'] ?? field['key'])
                                  .toString(),
                              helperText: field['description']?.toString(),
                              helperMaxLines: 4,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                  ),
                if (fields.isEmpty)
                  const Text(
                    'This provider does not declare configurable settings.',
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: saving || controllers.length != fields.length
                      ? null
                      : save,
                  icon: const Icon(Icons.lock_outline),
                  label: Text(saving ? 'Saving…' : 'Save securely'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Declared hosts',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  (((provider?['manifest'] as Map?)?['permissions']
                                  as Map?)?['network']
                              as List? ??
                          [])
                      .join('\n'),
                ),
              ],
            ),
          ),
  );
}
