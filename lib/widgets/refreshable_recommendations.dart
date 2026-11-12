import 'package:material_ui/material_ui.dart';
import 'package:yazhal/extensions/l10n.dart';
import 'package:yazhal/utilities/recommendation_session.dart';
import 'package:yazhal/widgets/recommended_songs_section.dart';

class RefreshableRecommendations extends StatefulWidget {
  const RefreshableRecommendations({
    super.key,
    required this.title,
    required this.scope,
    required this.load,
    this.limit = 15,
    this.excluded = const {},
    this.onAddSong,
  });
  final String title;
  final String scope;
  final int limit;
  final Set<String> excluded;
  final Future<List<dynamic>> Function(Set<String>, bool) load;
  final void Function(Map)? onAddSong;
  @override
  State<RefreshableRecommendations> createState() =>
      _RefreshableRecommendationsState();
}

class _RefreshableRecommendationsState
    extends State<RefreshableRecommendations> {
  late final RecommendationSession _session;
  bool _loading = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _session = RecommendationSession(
      limit: widget.limit,
      load: (excluded, refresh) => widget.load(excluded, refresh),
    );
    _refresh(initial: true);
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool initial = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final changed = await _session.refresh(
        initial: initial,
        excluded: widget.excluded,
      );
      if (mounted && !changed) _message = context.l10n!.noFreshRecommendations;
    } catch (_) {
      if (mounted) _message = context.l10n!.recommendationRefreshFailed;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      RecommendedSongsSection(
        title: widget.title,
        songs: _session.songs
            .where((s) => !widget.excluded.contains(s['ytid']?.toString()))
            .toList(),
        listKeyPrefix: widget.scope,
        onAddSong: widget.onAddSong,
        onRefresh: _loading ? null : _refresh,
        refreshing: _loading,
      ),
      if (_message != null)
        Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
    ],
  );
}
