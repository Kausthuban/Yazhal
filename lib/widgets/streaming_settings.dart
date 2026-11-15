import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/services/audio_relay_service.dart';

class StreamingSettings extends StatefulWidget {
  const StreamingSettings({super.key});
  @override
  State<StreamingSettings> createState() => _StreamingSettingsState();
}

class _StreamingSettingsState extends State<StreamingSettings> {
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final option in const <(String, String, String, bool)>[
        (
          'adaptiveStreaming',
          'Adaptive streaming',
          'Adjust quality at song boundaries using useful audio transfers. Audio quality above is the ceiling.',
          true,
        ),
        (
          'streamingDataSaver',
          'Streaming data saver',
          'Use low quality and disable next-song preloading.',
          false,
        ),
        (
          'preloadNextSong',
          'Preload next song',
          'Fetch at most 128 KiB of the actual next song near the end, when the current buffer is healthy.',
          true,
        ),
      ])
        SwitchListTile(
          title: Text(option.$2),
          subtitle: Text(option.$3),
          value:
              Hive.box('settings').get(option.$1, defaultValue: option.$4) ==
              true,
          onChanged: (value) async {
            await Hive.box('settings').put(option.$1, value);
            if ((option.$1 == 'streamingDataSaver' && value) ||
                (option.$1 == 'preloadNextSong' && !value))
              AudioRelayService.instance.cancelPreload();
            if (mounted) setState(() {});
          },
        ),
    ],
  );
}
