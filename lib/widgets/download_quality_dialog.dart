import 'package:material_ui/material_ui.dart';
import 'package:yazhal/services/extensions/native_extension_service.dart';
import 'package:yazhal/services/flac_extension_service.dart';
import 'package:yazhal/utilities/local_tracks.dart';

Future<String?> chooseDownloadQuality(BuildContext context, Map song) async {
  final options = <String, String>{};
  final descriptions = <String, String>{};
  var source = 'YouTube';
  if (isNativeExtensionTrack(song)) {
    final provider = NativeExtensionService.installed
        .where((p) => p['id'] == song['extensionId'])
        .firstOrNull;
    source = provider?['name']?.toString() ?? song['extensionId'].toString();
    if (!((provider?['manifest'] as Map?)?['type'] as List? ?? []).contains(
      'download_provider',
    )) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This extension provides metadata only. Search an audio/download provider for this recording.',
            ),
          ),
        );
      return null;
    }
    try {
      for (final q in await NativeExtensionService.instance.qualities(song)) {
        options[q.id] = q.label;
        descriptions[q.id] = q.description;
      }
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enable and configure this extension before downloading.',
            ),
          ),
        );
      return null;
    }
    if (options.isEmpty)
      options['ORIGINAL'] = 'Original quality offered by the provider';
  } else if (isExtensionTrack(song)) {
    source =
        FlacExtensionService.extensions
            .where((e) => e.id == song['extensionId'])
            .firstOrNull
            ?.name ??
        song['extensionId']?.toString() ??
        'FLAC catalogue';
    options['original'] = 'Original FLAC';
    descriptions['original'] = 'No conversion';
  } else {
    options.addAll({
      'high': 'High · best available original stream',
      'medium': 'Medium · balanced file size',
      'low': 'Low · smallest available stream',
    });
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Download quality',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose the source quality. Availability depends on the provider and your account. Audio is never relabelled as lossless.',
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final option in options.entries)
                    ListTile(
                      leading: const Icon(Icons.audio_file_outlined),
                      title: Text('${option.value} ($source)'),
                      subtitle: (descriptions[option.key] ?? '').isEmpty
                          ? null
                          : Text(descriptions[option.key]!),
                      onTap: () => Navigator.pop(context, option.key),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
