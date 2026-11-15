import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/services/headset_gestures.dart';
import 'package:yazhal/widgets/mini_player_bottom_space.dart';

class HeadsetSettingsPage extends StatefulWidget {
  const HeadsetSettingsPage({super.key});
  @override
  State<HeadsetSettingsPage> createState() => _HeadsetSettingsPageState();
}

class _HeadsetSettingsPageState extends State<HeadsetSettingsPage> {
  String? message;
  final box = Hive.box('settings');
  @override
  void dispose() {
    HeadsetRecording.stop();
    super.dispose();
  }

  Future<void> save(String key, dynamic value) async {
    await box.put(key, value);
    if (mounted) setState(() {});
  }

  void record() {
    setState(
      () => message = 'Press the headset button 4 or more times within 2 seconds. You can also use the tap button below.',
    );
    HeadsetRecording.arm(() async {
      if (!mounted) return;
      final taps = HeadsetRecording.taps.value;
      final window = (box.get('headsetTapWindowMs', defaultValue: 280) as num)
          .toInt();
      final valid =
          taps.length >= 4 &&
          taps.last - taps.first <= 2000 &&
          List.generate(
            taps.length - 1,
            (i) => taps[i + 1] - taps[i],
          ).every((n) => n <= window);
      if (valid) {
        await save('headsetPattern', taps);
        if (mounted)
          setState(() => message = 'Pattern saved (${taps.length} presses).');
      } else {
        setState(
          () => message =
              'Pattern not saved. Use at least 4 presses, keep gaps within $window ms, and finish within 2 seconds.',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Headset button actions')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SwitchListTile(
          title: const Text('Double and triple press'),
          subtitle: const Text(
            'Single: play/pause. Double: next. Triple: previous. Turn off for immediate single-press play/pause.',
          ),
          value: box.get('headsetMultiPress', defaultValue: true) == true,
          onChanged: (v) => save('headsetMultiPress', v),
        ),
        const Text(
          'A single button cannot distinguish one press from the first press of a double/triple instantly. Grouping waits only the tap window below, never the full 2-second recording window. Dedicated headset/Bluetooth Next and Previous events remain immediate.',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue:
              (box.get('headsetTapWindowMs', defaultValue: 280) as num).toInt(),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Tap grouping window',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final n in [180, 280, 400, 500])
              DropdownMenuItem(value: n, child: Text('$n ms')),
          ],
          onChanged: (v) => save('headsetTapWindowMs', v),
        ),
        for (final n in [1, 2, 3])
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: box
                  .get(
                    'headsetTap$n',
                    defaultValue: const {
                      1: 'toggle',
                      2: 'next',
                      3: 'previous',
                    }[n],
                  )
                  .toString(),
              decoration: InputDecoration(
                labelText: '$n ${n == 1 ? 'press' : 'presses'}',
                border: const OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'toggle', child: Text('Play / pause')),
                DropdownMenuItem(value: 'next', child: Text('Next song')),
                DropdownMenuItem(
                  value: 'previous',
                  child: Text('Previous song'),
                ),
              ],
              onChanged: (v) => save('headsetTap$n', v),
            ),
          ),
        const SizedBox(height: 24),
        const Text(
          'Custom pattern (minimum 4 presses)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: box
              .get('headsetPatternAction', defaultValue: 'seekForward')
              .toString(),
          decoration: const InputDecoration(
            labelText: 'Pattern action',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: 'seekForward',
              child: Text('Seek forward 10 seconds'),
            ),
            DropdownMenuItem(
              value: 'seekBackward',
              child: Text('Seek back 10 seconds'),
            ),
            DropdownMenuItem(value: 'play', child: Text('Play')),
            DropdownMenuItem(value: 'pause', child: Text('Pause')),
          ],
          onChanged: (v) => save('headsetPatternAction', v),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: record,
          icon: const Icon(Icons.fiber_manual_record),
          label: const Text('Record press pattern'),
        ),
        ValueListenableBuilder<List<int>>(
          valueListenable: HeadsetRecording.taps,
          builder: (_, taps, __) => OutlinedButton(
            onPressed: HeadsetRecording.active
                ? HeadsetRecording.capture
                : null,
            child: Text('Tap to record · ${taps.length} presses'),
          ),
        ),
        if (message != null) Text(message!),
        const MiniPlayerBottomSpace(),
      ],
    ),
  );
}
