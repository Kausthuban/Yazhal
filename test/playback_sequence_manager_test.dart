import 'package:flutter_test/flutter_test.dart';
import 'package:yazhal/services/playback_sequence_manager.dart';

Map song(String id) => {'ytid': id, 'queueEntryId': id};
List<String> ids(PlaybackSequenceManager manager) =>
    manager.entries.map((s) => s['ytid'] as String).toList();
void main() {
  test('tap middle of context retains previous and upcoming songs', () {
    final m = PlaybackSequenceManager()
      ..replaceContext([song('a'), song('b'), song('c')], startIndex: 1);
    expect(m.current?['ytid'], 'b');
    expect(m.next?['ytid'], 'c');
    expect(m.hasPrevious, true);
    expect(m.originalContext.map((s) => s['ytid']), ['a', 'b', 'c']);
  });
  test(
    'manual queue plays before context, then context resumes exactly once',
    () {
      final m = PlaybackSequenceManager()
        ..replaceContext([song('a'), song('b'), song('c')]);
      m
        ..appendManual([song('x'), song('y')])
        ..entries.insert(m.manualInsertionIndex(playNext: true), {
          ...song('z'),
          'isManuallyAdded': true,
        });
      expect(ids(m), ['a', 'z', 'x', 'y', 'b', 'c']);
      final played = <String>[];
      while (m.hasNext) {
        m.currentIndex++;
        played.add(m.current!['ytid']);
      }
      expect(played, ['z', 'x', 'y', 'b', 'c']);
      expect(m.originalContext.map((s) => s['ytid']), ['a', 'b', 'c']);
    },
  );
  test('new context retains only unplayed manual additions', () {
    final m = PlaybackSequenceManager()
      ..replaceContext([song('a'), song('b')])
      ..appendManual([song('x'), song('y')])
      ..currentIndex = 1
      ..replaceContext([song('d'), song('e')]);
    expect(ids(m), ['d', 'y', 'e']);
  });
  test(
    'clearing manual additions preserves current and context continuation',
    () {
      final m = PlaybackSequenceManager()
        ..replaceContext([song('a'), song('b')])
        ..appendManual([song('x'), song('y')])
        ..currentIndex = 1
        ..clearManual();
      expect(ids(m), ['a', 'x', 'b']);
      expect(m.current?['ytid'], 'x');
    },
  );
  test('duplicate tracks retain distinct queue occurrences', () {
    final m = PlaybackSequenceManager()
      ..replaceContext([
        song('first')..['ytid'] = 'same',
        song('second')..['ytid'] = 'same',
        song('c'),
      ], startIndex: 1);
    expect(m.current!['queueEntryId'], 'second');
    expect(m.next!['ytid'], 'c');
  });
  test('reorder preserves the currently playing occurrence', () {
    final m = PlaybackSequenceManager()
      ..replaceContext([song('a'), song('b'), song('c')], startIndex: 1)
      ..move(2, 0);
    expect(ids(m), ['c', 'a', 'b']);
    expect(m.current!['ytid'], 'b');
  });
  test(
    'shuffle retains selected start and manual priority without losing context',
    () {
      final m = PlaybackSequenceManager()
        ..appendManual([song('old'), song('x')])
        ..replaceContext(
          [song('a'), song('b'), song('c')],
          startIndex: 1,
          shuffle: true,
        );
      expect(ids(m).take(2), ['b', 'x']);
      expect(ids(m).toSet(), {'a', 'b', 'c', 'x'});
      expect(m.originalContext.map((s) => s['ytid']), ['a', 'b', 'c']);
    },
  );
  test('empty sequence never advertises navigation', () {
    final m = PlaybackSequenceManager()..replaceContext([]);
    expect(m.hasNext, false);
    expect(m.hasPrevious, false);
    expect(m.current, null);
  });
  test(
    'repeat all starts the context again without consumed manual requests',
    () {
      final m = PlaybackSequenceManager()
        ..replaceContext([song('a'), song('b')])
        ..appendManual([song('x')])
        ..currentIndex = 2
        ..restartContextCycle();
      expect(ids(m), ['a', 'b']);
      expect(m.current!['ytid'], 'a');
    },
  );
}
