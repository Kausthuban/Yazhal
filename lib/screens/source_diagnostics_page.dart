import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/services/extensions/native_extension_service.dart';
import 'package:yazhal/services/settings_manager.dart' show offlineMode;
import 'package:yazhal/services/source_diagnostics.dart';
import 'package:yazhal/widgets/mini_player_bottom_space.dart';

class SourceDiagnosticsPage extends StatefulWidget {
  const SourceDiagnosticsPage({this.runCheck, super.key});
  final Future<SourceDiagnosticReport> Function()? runCheck;
  @override
  State<SourceDiagnosticsPage> createState() => _SourceDiagnosticsPageState();
}

class _SourceDiagnosticsPageState extends State<SourceDiagnosticsPage> {
  bool busy = false;
  SourceDiagnosticReport? report;
  String? message;
  Future<void> run() async {
    if (busy) return;
    if (offlineMode.value) {
      setState(
        () => message =
            'Turn off offline mode in Settings before checking online sources.',
      );
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final provider = NativeExtensionService.installed
          .where((p) => p['id'] == 'jiosaavn')
          .firstOrNull;
      final result =
          await (widget.runCheck?.call() ??
              SourceDiagnostics().run(
                adapterVersion:
                    provider?['version']?.toString() ?? 'Not installed',
                adapterProbe: provider?['enabled'] == true
                    ? () async => (await NativeExtensionService.instance.search(
                        'jiosaavn',
                        'music',
                      )).length
                    : null,
              ));
      if (mounted) setState(() => report = result);
    } catch (_) {
      if (mounted)
        setState(
          () => message = 'The check could not finish. Try again; credentials and response bodies were not recorded.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Source check')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Why is JioSaavn not responding?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Check DNS, secure connection, the search API and your installed adapter on this device. The check uses a fixed test query, downloads no audio and records no credentials or listening history.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : run,
          icon: const Icon(Icons.network_check),
          label: const Text('Run source check'),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(message!),
          ),
        if (report != null) ...[
          const SizedBox(height: 16),
          Text(report!.summary, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final check in report!.checks)
            Card(
              child: ListTile(
                leading: Icon(
                  check.state == 'passed'
                      ? Icons.check_circle_outline
                      : check.state == 'skipped'
                      ? Icons.remove_circle_outline
                      : Icons.error_outline,
                ),
                title: Text('${check.name} · ${check.state}'),
                subtitle: Text(check.detail),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report!.toText()));
              if (context.mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Diagnostic report copied. No credentials or history included.',
                    ),
                  ),
                );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy diagnostic report'),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'A website loading does not prove its API is available. If the API returns HTML or refuses requests, choose YouTube (Musify) or another source. A diagnostic result identifies the failing stage; it cannot by itself prove a global outage or a regional block.',
        ),
        const MiniPlayerBottomSpace(),
      ],
    ),
  );
}
