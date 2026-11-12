/// Counts starts of matching file sources, excluding prepare, buffering,
/// pause/resume notifications, stale sources, and online streams.
class OfflinePlaySession {
  Map? _source;
  Map? _pending;
  void reset() {
    _source = null;
    _pending = null;
  }

  void prepare(Map song, {required bool offline}) {
    _source = offline ? Map.from(song) : null;
    _pending = _source;
  }

  void replay() {
    _pending = _source;
  }

  Map? takeStarted({
    required bool playing,
    required bool ready,
    required Object? sourceId,
  }) {
    final song = _pending;
    if (song == null ||
        !playing ||
        !ready ||
        sourceId?.toString() != song['ytid']?.toString())
      return null;
    _pending = null;
    return Map.from(song);
  }
}
