import 'dart:math';

/// Recent plays outweigh a large unused library. Language is inferred from
/// explicit metadata or script, never from the user's location or name.
class ListeningProfile {
  ListeningProfile(Iterable<Map> history, {this.preferredLanguage}) {
    var index = 0;
    for (final song in history.take(100)) {
      final weight =
          1 /
          (1 + index++ / 5) *
          (1 +
              log(
                1 +
                    ((song['listeningCount'] ?? song['plays'] ?? 1) as num)
                        .clamp(0, 100),
              ));
      final artist = (song['artist'] ?? '').toString().trim();
      if (artist.isNotEmpty)
        artists.update(artist, (n) => n + weight, ifAbsent: () => weight);
      final language = languageOf(song);
      if (language != null)
        artistLanguages.putIfAbsent(artist, () => <String>{}).add(language);
      if (language != null)
        languages.update(
          language,
          (n) => n + pow(.5, index - 1).toDouble(),
          ifAbsent: () => pow(.5, index - 1).toDouble(),
        );
    }
  }
  final String? preferredLanguage;
  final artistLanguages = <String, Set<String>>{};
  final artists = <String, double>{};
  final languages = <String, double>{};
  static String? languageOf(Map song) {
    final metadata = song['providerTrack'] is Map
        ? song['providerTrack'] as Map
        : const {};
    final explicit =
        (song['language'] ?? metadata['language'] ?? metadata['lang'] ?? '')
            .toString()
            .toLowerCase();
    const aliases = {
      'ta': 'tamil',
      'hi': 'hindi',
      'te': 'telugu',
      'ml': 'malayalam',
      'kn': 'kannada',
      'en': 'english',
      'pa': 'punjabi',
      'bn': 'bengali',
    };
    for (final entry in aliases.entries) {
      if (explicit == entry.key ||
          explicit.startsWith('${entry.key}-') ||
          explicit.contains(entry.value))
        return entry.value;
    }
    final text = '${song['title']} ${song['album']}';
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return 'tamil';
    if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(text)) return 'telugu';
    if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(text)) return 'malayalam';
    if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(text)) return 'kannada';
    return null;
  }

  String? get language {
    if (preferredLanguage != null && preferredLanguage!.isNotEmpty)
      return preferredLanguage;
    if (languages.isEmpty) return null;
    return (languages.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .first
        .key;
  }

  List<String> get queries {
    final ranked =
        artists.entries
            .where(
              (e) =>
                  language == null ||
                  (artistLanguages[e.key]?.contains(language) ?? false),
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return ranked
        .take(3)
        .map((e) => '${e.key}${language == null ? '' : ' $language'}')
        .toList();
  }

  double affinity(Map song) {
    final artist = (song['artist'] ?? '').toString().toLowerCase();
    final artistScore = artists.entries
        .where((e) => artist.contains(e.key.toLowerCase()))
        .fold<double>(0, (n, e) => n + e.value);
    final lang = languageOf(song);
    return artistScore +
        (language != null && lang == language ? 20 : 0) -
        (language != null && lang != null && lang != language ? 100 : 0);
  }

  List<Map> rank(Iterable<Map> songs) {
    final list = songs.toList()
      ..shuffle()
      ..sort((a, b) => affinity(b).compareTo(affinity(a)));
    return list;
  }
}
