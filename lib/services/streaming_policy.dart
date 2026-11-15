import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

/// Uses useful audio transfers, not separate speed-test downloads.
class StreamingPolicy {
  static final instance = StreamingPolicy();
  final quality = ValueNotifier<String>('high');
  double? _kbps;
  int _good = 0;
  bool get adaptive =>
      Hive.box('settings').get('adaptiveStreaming', defaultValue: true) == true;
  bool get dataSaver =>
      Hive.box('settings').get('streamingDataSaver', defaultValue: false) ==
      true;
  bool get preloadEnabled =>
      Hive.box('settings').get('preloadNextSong', defaultValue: true) == true;
  double? get estimatedKbps => _kbps;
  String effectiveQuality(String ceiling) {
    const levels = ['low', 'medium', 'high'];
    final selected = levels.contains(ceiling) ? ceiling : 'high';
    if (dataSaver) return 'low';
    if (!adaptive) return selected;
    return levels[min(levels.indexOf(selected), levels.indexOf(quality.value))];
  }

  void observe(int bytes, Duration elapsed) {
    if (bytes < 16384 || elapsed.inMicroseconds <= 0) return;
    final sample = (bytes * 8 / elapsed.inMicroseconds * 1000)
        .clamp(1, 1000000)
        .toDouble();
    _kbps = _kbps == null
        ? sample
        : sample < _kbps!
        ? .7 * sample + .3 * _kbps!
        : .2 * sample + .8 * _kbps!;
    final next = _kbps! < 350
        ? 'low'
        : _kbps! < 900
        ? 'medium'
        : 'high';
    const rank = {'low': 0, 'medium': 1, 'high': 2};
    if (rank[next]! < rank[quality.value]!) {
      quality.value = next;
      _good = 0;
    } else if (next != quality.value && ++_good >= 3) {
      quality.value = next;
      _good = 0;
    }
  }

  void stalled() {
    _good = 0;
    _kbps = (_kbps ?? 300) * .5;
    quality.value = 'low';
  }

  bool shouldPreload({
    required Duration remaining,
    required Duration bufferedAhead,
    required bool playing,
  }) =>
      preloadEnabled &&
      !dataSaver &&
      playing &&
      remaining > const Duration(seconds: 3) &&
      bufferedAhead >= const Duration(seconds: 5) &&
      (_kbps == null || _kbps! >= 350);
}
