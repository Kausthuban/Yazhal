import 'package:yazhal/services/proxy_manager.dart';
import 'package:yazhal/utilities/formatter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// The original Musify YouTube song search, now an explicit provider.
class YouTubeSearchProvider {
  YouTubeSearchProvider({
    Future<Iterable<Video>> Function(String)? searchVideos,
  }) : _searchVideos =
           searchVideos ?? ((query) => ytClient.search.search(query));
  final Future<Iterable<Video>> Function(String) _searchVideos;
  Future<List<Map<String, dynamic>>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final videos = await _searchVideos(query.trim())
        .timeout(const Duration(seconds: 25));
    return videos
        .take(50)
        .indexed
        .map(
          (entry) => {
            ...returnSongLayout(entry.$1, entry.$2),
            'source': 'youtube',
            'attribution': 'YouTube · original Musify search',
          },
        )
        .toList();
  }
}
