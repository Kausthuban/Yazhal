import 'package:material_ui/material_ui.dart';
import 'package:yazhal/services/extensions/native_extension_service.dart';
import 'package:yazhal/utilities/url_launcher.dart';

class SourceCredits extends StatelessWidget {
  const SourceCredits({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Sources & acknowledgements',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      for (final credit in const <(String, String, String)>[
        (
          'JioSaavn adapter · HemanthJabalpuri; Mornye contributors',
          'Bundled catalogue and up-to-320 kbps AAC adapter; original notices, LGPL-3.0 and GPL terms included in assets/providers.',
          'https://github.com/mornyeapp/Mornye-Extension',
        ),
        (
          'Apple iTunes Search API',
          'Catalogue artwork and metadata matching only. No Apple Music audio or DRM download integration.',
          'https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/',
        ),
        (
          'Musify · Valeri Gokadze',
          'Original app and playback foundation · GPL-3.0-or-later',
          'https://github.com/gokadzev/Musify',
        ),
        (
          'Mornye · Zarz Eleutherius (zarzet) & contributors',
          'Extension SDK contracts, repository workflow, metadata and lyrics integration design · LGPL-3.0-only',
          'https://github.com/mornyeapp/Mornye',
        ),
        (
          'SpotiFLAC / Mornye Extension registry · zarzet & provider authors',
          'Community extension packages. Individual author, version and license are preserved with each installation.',
          'https://github.com/mornyeapp/Mornye-Extension',
        ),
        (
          'QuickJS · Fabrice Bellard & Charlie Gordon',
          'JavaScript engine · MIT. Flutter bindings: flutter_qjs_next by NanCunChild, based on ekibun/flutter_qjs.',
          'https://github.com/NanCunChild/flutter_qjs_next',
        ),
        (
          'MusicBrainz & Cover Art Archive',
          'Offline metadata and cover-art lookup. Artwork rights remain with the respective owners.',
          'https://musicbrainz.org',
        ),
        (
          'LRCLIB and lyric providers',
          'Built-in synced/plain lyrics: LRCLIB, lyrics.ovh, paroles.net, lyricsmania.com. Lyrics remain the property of their rights holders.',
          'https://lrclib.net',
        ),
        (
          'Live Music Archive · Internet Archive',
          'Optional FLAC catalog for live recordings. Respect each recording’s rights and attribution.',
          'https://archive.org/details/etree',
        ),
      ])
        Card(
          child: ListTile(
            title: Text(credit.$1),
            subtitle: Text(credit.$2),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchURL(Uri.parse(credit.$3)),
          ),
        ),
      for (final extension in NativeExtensionService.installed)
        Card(
          child: ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: Text('${extension['name']} · ${extension['version']}'),
            subtitle: Text(
              'Author: ${extension['author']}\nRepository: ${extension['repository']}',
            ),
            onTap: () async {
              try {
                final package = await NativeExtensionService.instance.load(
                  extension['id'].toString(),
                  requireEnabled: false,
                );
                if (!context.mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('${package.name} · licenses'),
                    content: SingleChildScrollView(
                      child: SelectableText(
                        package.licenses.entries
                            .map((e) => '${e.key}\n${e.value}')
                            .join('\n\n'),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              } catch (_) {
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Package notices are unavailable. Check the installed package.',
                      ),
                    ),
                  );
              }
            },
          ),
        ),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Yazhal is maintained by Kausthuban R S. The harp logo was supplied by the project owner. Ported interfaces and original contributions are distinguished in NOTICE.md; authorship of upstream work is retained.',
        ),
      ),
    ],
  );
}
