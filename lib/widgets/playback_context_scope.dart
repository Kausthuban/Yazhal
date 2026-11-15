import 'package:flutter/widgets.dart';

/// Carries the ordered rows actually displayed, including duplicate occurrences.
class PlaybackContextScope extends InheritedWidget {
  const PlaybackContextScope({
    required this.songs,
    required super.child,
    this.title = '',
    super.key,
  });
  final List<Map> songs;
  final String title;
  static PlaybackContextScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaybackContextScope>();
  @override
  bool updateShouldNotify(PlaybackContextScope oldWidget) =>
      !identical(songs, oldWidget.songs) || title != oldWidget.title;
}
