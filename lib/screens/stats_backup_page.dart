import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yazhal/services/stats_backup_service.dart';

class StatsBackupPage extends StatefulWidget {
  const StatsBackupPage({super.key});
  @override
  State<StatsBackupPage> createState() => _StatsBackupPageState();
}

class _StatsBackupPageState extends State<StatsBackupPage> {
  bool busy = false;
  String? message;
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
          () => message = e is FormatException ? e.message : 'The backup operation failed. Your music and settings were not changed.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String get filename =>
      'Yazhal-Stats-${DateTime.now().toIso8601String().substring(0, 10)}.json';
  Future<void> save() async {
    final path = await FilePicker.saveFile(
      fileName: filename,
      mimeType: 'application/json',
      bytes: await StatsBackupService.export(),
    );
    if (mounted)
      setState(
        () => message = path == null
            ? 'Export cancelled.'
            : 'Statistics backup exported.',
      );
  }

  Future<void> share() async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(await StatsBackupService.export(), flush: true);
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        title: 'Yazhal listening statistics',
        files: [XFile(file.path, mimeType: 'application/json')],
        fileNameOverrides: [filename],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
    if (mounted) setState(() => message = 'Share sheet opened.');
  }

  Future<void> restore() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return;
    if ((file.lengthSync() ?? 0) > StatsBackupService.maxBytes)
      throw const FormatException('Backup exceeds 5 MiB');
    final bytes = <int>[];
    await for (final chunk in file.readAsByteStream().timeout(
      const Duration(seconds: 20),
    )) {
      if (bytes.length + chunk.length > StatsBackupService.maxBytes)
        throw const FormatException('Backup exceeds 5 MiB');
      bytes.addAll(chunk);
    }
    final data = StatsBackupService.decode(bytes);
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore listening statistics?'),
        content: const Text(
          'Replace the current statistics with this file? Music, playlists, downloads, settings and provider credentials will stay unchanged. Restoring the same file again will not add duplicate plays.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace statistics'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await StatsBackupService.restore(data);
    if (mounted) setState(() => message = 'Statistics restored.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local statistics backup')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          Icons.save_outlined,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 20),
        Text(
          'Your stats, in one file',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Export a readable JSON file with listening totals, song play counts and offline listening history. Save it on your device or share it using any app. No account, login or cloud service is required.',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : () => run(save),
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Export backup file'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : () => run(share),
          icon: const Icon(Icons.share_outlined),
          label: const Text('Share backup file'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : () => run(restore),
          icon: const Icon(Icons.restore),
          label: const Text('Restore from file'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(message!),
          ),
        const SizedBox(height: 24),
        const Text(
          'The backup contains listening history, so share it only with people you choose. It excludes audio files, local file paths, account tokens, extension settings and pairing secrets.',
        ),
      ],
    ),
  );
}
