/// Keeps the last successful batch while a refresh is in flight. History is
/// bounded; exclusions include everything displayed during the current cycle.
class RecommendationSession {
  RecommendationSession({required this.limit, required this.load});
  final int limit;
  final Future<List<dynamic>> Function(Set<String> excluded, bool refresh) load;
  List<dynamic> songs = [];
  final Set<String> _seen = {};
  bool busy = false;
  bool _disposed = false;
  int _request = 0;

  Future<bool> refresh({
    bool initial = false,
    Set<String> excluded = const {},
  }) async {
    if (busy || _disposed) return false;
    busy = true;
    final request = ++_request;
    final blocked = {..._seen, ...excluded};
    try {
      final candidates = await load(blocked, !initial);
      if (_disposed || request != _request) return false;
      final unique = <String>{};
      final next = candidates
          .whereType<Map>()
          .where((s) {
            final id = s['ytid']?.toString() ?? '';
            return id.isNotEmpty && !blocked.contains(id) && unique.add(id);
          })
          .take(limit)
          .toList();
      if (next.isEmpty) return false;
      songs = next;
      _seen.addAll(unique.take(limit));
      if (_seen.length > 150) {
        final keep = _seen.skip(_seen.length - 100).toList();
        _seen
          ..clear()
          ..addAll(keep);
      }
      return true;
    } finally {
      if (!_disposed && request == _request) busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    _request++;
  }
}
