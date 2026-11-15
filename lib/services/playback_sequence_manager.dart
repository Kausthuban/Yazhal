import 'package:yazhal/utilities/queue_entry_utils.dart';

/// One ordered playback projection shared by UI, media sessions and completion.
/// Context identity/order is independent of manually inserted queue occurrences.
class PlaybackSequenceManager {
  final List<Map> entries = [];
  final List<Map> _context = [];
  int currentIndex = -1;
  String contextTitle = '';
  List<Map> get originalContext => List.unmodifiable(_context);
  List<Map> get pendingManual => entries
      .skip(currentIndex + 1)
      .where((s) => s['isManuallyAdded'] == true && s['isAutoPicked'] != true)
      .toList();
  Map? get current => currentIndex >= 0 && currentIndex < entries.length
      ? entries[currentIndex]
      : null;
  Map? get next => hasNext ? entries[currentIndex + 1] : null;
  bool get hasNext => current != null && currentIndex + 1 < entries.length;
  bool get hasPrevious => current != null && currentIndex > 0;

  void replaceContext(
    List<Map> songs, {
    int startIndex = 0,
    bool shuffle = false,
    String title = '',
  }) {
    final manual = pendingManual;
    _context
      ..clear()
      ..addAll(
        songs.map(
          (s) => {...s, 'isManuallyAdded': false, 'isAutoPicked': false},
        ),
      );
    contextTitle = title;
    entries
      ..clear()
      ..addAll(_context);
    if (entries.isEmpty) {
      currentIndex = -1;
      return;
    }
    currentIndex = startIndex.clamp(0, entries.length - 1);
    if (shuffle) {
      final start = entries.removeAt(currentIndex);
      entries
        ..shuffle()
        ..insert(0, start);
      currentIndex = 0;
    }
    entries.insertAll(currentIndex + 1, manual);
  }

  /// Add to Queue follows existing manual entries, ahead of context continuation.
  int manualInsertionIndex({required bool playNext}) {
    if (entries.isEmpty) return 0;
    var index = (currentIndex + 1).clamp(0, entries.length);
    if (!playNext) {
      while (index < entries.length &&
          entries[index]['isManuallyAdded'] == true) {
        index++;
      }
    }
    return index;
  }

  void appendManual(List<Map> songs) {
    final index = manualInsertionIndex(playNext: false);
    entries.insertAll(index, songs.map((s) => {...s, 'isManuallyAdded': true}));
    if (currentIndex < 0 && entries.isNotEmpty) currentIndex = 0;
  }

  void clearManual() {
    final currentEntry = current;
    entries.removeWhere(
      (s) => !identical(s, currentEntry) && s['isManuallyAdded'] == true,
    );
    currentIndex = currentEntry == null ? -1 : entries.indexOf(currentEntry);
  }

  void forget(Map removed) {
    _context.removeWhere((s) => s['queueEntryId'] == removed['queueEntryId']);
  }

  void move(int oldIndex, int newIndex) {
    final entry = entries.removeAt(oldIndex);
    entries.insert(newIndex, entry);
    currentIndex = indexAfterQueueReorder(currentIndex, oldIndex, newIndex);
  }

  /// Consumed manual requests do not repeat on subsequent context cycles.
  void restartContextCycle() {
    if (_context.isNotEmpty)
      entries.removeWhere((s) => s['isManuallyAdded'] == true);
    currentIndex = entries.isEmpty ? -1 : 0;
  }

  void clear() {
    entries.clear();
    _context.clear();
    currentIndex = -1;
    contextTitle = '';
  }
}
