import 'package:material_ui/material_ui.dart';
import 'package:yazhal/services/extensions/native_extension_service.dart';
import 'package:yazhal/utilities/url_launcher.dart';
import 'package:yazhal/widgets/mini_player_bottom_space.dart';

class SourceHelpButton extends StatelessWidget {
  const SourceHelpButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'How music sources work',
    icon: const Icon(Icons.help_outline),
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const SourceHelpPage()),
    ),
  );
}

class SourceHelpPage extends StatelessWidget {
  const SourceHelpPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Music source guide')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Choose where your music comes from',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          '1. Open Settings → Music sources & repositories.\n\n'
          '2. Add a repository containing registry.json. Browse an extension, review its author and network permissions, then install and enable it.\n\n'
          '3. Tap the small provider button inside the left of the Search bar to select a source. If a source is unavailable, use Retry or Change provider. A metadata source supplies names, albums, artwork or lyrics. Only a download/audio provider can supply playable audio.\n\n'
          '4. For a metadata-only result, open Track information and choose a compatible audio provider. Yazhal asks before matching a different recording.\n\n'
          '5. Tap Download on a song and choose an offered quality. The bitrate depends on that source and recording. A 128 kbps file cannot be made lossless by relabelling it.\n\n'
          'Yazhal has no app account. Some independent music services require their own subscription or provider authorization. Credentials stay on this device and out of statistics backups.',
        ),
        const SizedBox(height: 20),
        const ListTile(
          leading: Icon(Icons.smart_display_outlined),
          title: Text('YouTube (Musify)'),
          subtitle: Text(
            'The original Musify search is available in the provider picker. Select it to enable it. Classic Musify search also includes artists, albums, playlists and search history. It never silently replaces another provider, and artwork still uses the existing non-YouTube artwork policy.',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.library_music),
          title: const Text('Amazon Music'),
          subtitle: const Text(
            'Official playback is not configured. Amazon requires approved developer access and authorization and currently provides no public Music SDK. Adding a repository does not grant this access. The current Mornye Amazon extension also needs its signed-session/session-grant host and encrypted-transfer adapter. This build reports that requirement instead of claiming Amazon is ready. A compatible authorized adapter may be selected when available.',
          ),
          onTap: () => launchURL(
            Uri.parse(
              'https://developer.amazon.com/docs/music/get_started_program-overview.html',
            ),
          ),
        ),
        const ListTile(
          leading: Icon(Icons.album_outlined),
          title: Text('Apple Music and Mornye'),
          subtitle: Text(
            'Mornye’s Apple extension supplies metadata and lyrics. That is different from full-song playback. Official MusicKit playback needs your own developer token, user authorization and an eligible subscription. DRM-protected Apple/Amazon downloads are not converted into unprotected files by Yazhal.',
          ),
        ),
        const ListTile(
          leading: Icon(Icons.high_quality),
          title: Text('Higher quality'),
          subtitle: Text(
            'JioSaavn can offer AAC up to 320 kbps. FLAC sources offer only the qualities listed by their own extension. High is the initial streaming setting; adaptive quality can reduce it on a slow connection. Check source information for the actual format.',
          ),
        ),
        const ListTile(
          leading: Icon(Icons.storage),
          title: Text('Temporary buffer vs downloads'),
          subtitle: Text(
            'The playback buffer is disposable and bounded by your cache setting. Download saves a separate library copy to your selected download folder. Clearing the temporary cache keeps your downloaded music. Data saver disables speculative next-song downloads.',
          ),
        ),
        const SizedBox(height: 16),
        const SelectableText(recommendedExtensionRegistry),
        const SizedBox(height: 8),
        const Text(
          'Repositories may change or be unavailable. Use only extensions you trust. Each installed extension retains its author and license in Music sources and About.',
        ),
        const MiniPlayerBottomSpace(),
      ],
    ),
  );
}
