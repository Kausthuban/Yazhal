import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

class HeadsetRecording {
  static final taps = ValueNotifier<List<int>>([]);
  static bool active = false;
  static DateTime? _start;
  static Timer? _timer;
  static VoidCallback? onComplete;
  static void arm(VoidCallback complete) {
    stop();
    taps.value = [];
    active = true;
    onComplete = complete;
  }

  static void capture() {
    if (!active) return;
    _start ??= DateTime.now();
    _timer ??= Timer(const Duration(seconds: 2), () {
      active = false;
      _timer = null;
      onComplete?.call();
    });
    taps.value = [
      ...taps.value,
      DateTime.now().difference(_start!).inMilliseconds,
    ];
  }

  static void stop() {
    active = false;
    _timer?.cancel();
    _timer = null;
    _start = null;
    onComplete = null;
  }
}

String resolveHeadsetPattern(List<int> taps, Map settings) {
  if (taps.isEmpty) return 'none';
  if (taps.length < 4)
    return (settings['headsetTap${taps.length}'] ??
            const {1: 'toggle', 2: 'next', 3: 'previous'}[taps.length])
        .toString();
  final pattern = (settings['headsetPattern'] as List? ?? [])
      .whereType<num>()
      .map((n) => n.toInt())
      .toList();
  if (pattern.length < 4 ||
      pattern.length != taps.length ||
      taps.last - taps.first > 2000)
    return 'none';
  for (var i = 1; i < taps.length; i++) {
    final actual = taps[i] - taps[i - 1],
        expected = pattern[i] - pattern[i - 1];
    if ((actual - expected).abs() > (expected * .3).clamp(60, 120))
      return 'none';
  }
  return (settings['headsetPatternAction'] ?? 'seekForward').toString();
}

class HeadsetGestureRouter {
  HeadsetGestureRouter(this.dispatch, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final Future<void> Function(String action) dispatch;
  final DateTime Function() clock;
  final _taps = <int>[];
  Timer? _timer;
  void press() {
    if (HeadsetRecording.active) {
      HeadsetRecording.capture();
      return;
    }
    final box = Hive.box('settings');
    if (box.get('headsetMultiPress', defaultValue: true) != true) {
      unawaited(dispatch('toggle'));
      return;
    }
    final now = clock().millisecondsSinceEpoch;
    if (_taps.isNotEmpty && now - _taps.first > 2000) _taps.clear();
    _taps.add(now);
    _timer?.cancel();
    final window = (box.get('headsetTapWindowMs', defaultValue: 280) as num)
        .toInt()
        .clamp(150, 500);
    _timer = Timer(Duration(milliseconds: window), () {
      final settings = {
        for (final key in [
          'headsetTap1',
          'headsetTap2',
          'headsetTap3',
          'headsetPattern',
          'headsetPatternAction',
        ])
          key: box.get(key),
      }..removeWhere((_, v) => v == null);
      final action = resolveHeadsetPattern(List.of(_taps), settings);
      _taps.clear();
      if (action != 'none') unawaited(dispatch(action));
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _taps.clear();
  }
}
