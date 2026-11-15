import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/localization/app_localizations.dart';
import 'package:yazhal/screens/headset_settings_page.dart';
import 'package:yazhal/screens/playback_cache_page.dart';
import 'package:yazhal/screens/source_help_page.dart';
import 'package:yazhal/services/common_services.dart';
import 'package:yazhal/services/headset_gestures.dart';
import 'package:yazhal/widgets/player_dismiss_gesture.dart';
import 'package:yazhal/widgets/selection_nav_host.dart';
import 'package:yazhal/widgets/song_bar.dart';
import 'package:yazhal/widgets/song_selection_region.dart';
import 'package:yazhal/widgets/startup_gate.dart';

Widget app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);
void main() {
  late Directory directory;
  setUpAll(() async {
    final font = Platform.environment['YAZHAL_FEEDBACK_TEST_FONT'];
    if (font != null) {
      final loader = FontLoader('FeedbackSans')
        ..addFont(
          Future.value(ByteData.sublistView(await File(font).readAsBytes())),
        );
      await loader.load();
      final icons = Platform.environment['YAZHAL_FEEDBACK_ICON_FONT'];
      if (icons != null) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(
                ByteData.sublistView(await File(icons).readAsBytes()),
              ),
            ))
            .load();
      }
    }
    directory = await Directory.systemTemp.createTemp('yazhal_feedback_ui');
    Hive.init(directory.path);
    for (final b in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(b);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  testWidgets(
    'splash paints without waiting for audio or storage initialization',
    (tester) async {
      final pending = Completer<void>();
      await tester.pumpWidget(
        StartupGate(
          initialize: () => pending.future,
          child: const MaterialApp(home: Text('Ready')),
        ),
      );
      expect(find.text('Yazhal'), findsOneWidget);
      expect(find.text('Ready'), findsNothing);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Ready'), findsOneWidget);
    },
  );
  testWidgets('swiping down returns to the previous screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const PlayerDismissGesture(
                      child: Scaffold(body: Center(child: Text('Playing'))),
                    ),
                  ),
                ),
                child: const Text('Open player'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open player'));
    await tester.pumpAndSettle();
    await tester.fling(find.text('Playing'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Open player'), findsOneWidget);
    expect(find.text('Playing'), findsNothing);
  });
  testWidgets('selection replaces the navigation bar only after long press', (
    tester,
  ) async {
    final rows = [
      {'ytid': 'local:a', 'title': 'One', 'artist': 'Artist'},
    ];
    selectionNavigationBar.value = null;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SelectionNavHost(
            enabled: true,
            child: SongSelectionRegion(
              songs: rows,
              child: ListView(
                children: [SongBar(rows.first, true, onPlay: () {})],
              ),
            ),
          ),
          bottomNavigationBar: ValueListenableBuilder<Widget?>(
            valueListenable: selectionNavigationBar,
            builder: (_, bar, __) => bar ?? const Text('Navigation'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Select songs'), findsNothing);
    expect(find.text('Navigation'), findsOneWidget);
    await tester.longPress(find.text('One'));
    await tester.pumpAndSettle();
    expect(find.text('Navigation'), findsNothing);
    expect(find.byIcon(Icons.queue_music), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Navigation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'large imported list builds only visible rows and keeps selection usable',
    (tester) async {
      final songs = [
        for (var i = 0; i < 5000; i++)
          {
            'ytid': 'local:$i',
            'title': 'Imported song $i',
            'artist': 'Artist $i',
            'source': 'local',
          },
      ];
      userOfflineSongs.value = songs;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SongSelectionRegion(
              songs: songs,
              child: ListView.builder(
                itemCount: songs.length,
                itemBuilder: (_, i) => SongBar(songs[i], true, onPlay: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SongBar).evaluate().length, lessThan(40));
      await tester.fling(find.byType(ListView), const Offset(0, -3500), 8000);
      await tester.pumpAndSettle();
      expect(find.byType(SongBar).evaluate().length, lessThan(40));
      expect(tester.takeException(), isNull);
      userOfflineSongs.value = [];
    },
  );
  testWidgets(
    'headset tap grouping does not wait the custom two-second window',
    (tester) async {
      final actions = <String>[];
      final router = HeadsetGestureRouter((a) async => actions.add(a))..press();
      await tester.pump(const Duration(milliseconds: 100));
      router.press();
      await tester.pump(const Duration(milliseconds: 280));
      expect(actions, ['next']);
      router.cancel();
    },
  );
  for (final entry in <String, Widget>{
    'source-help': const SourceHelpPage(),
    'headset': const HeadsetSettingsPage(),
    'buffer': const PlaybackCachePage(),
  }.entries) {
    testWidgets('${entry.key} fits a narrow phone with larger text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const capture = Key('capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily:
                  Platform.environment['YAZHAL_FEEDBACK_TEST_FONT'] == null
                  ? null
                  : 'FeedbackSans',
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: entry.value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final out = Platform.environment['YAZHAL_FEEDBACK_CAPTURE_DIR'];
      if (out != null) {
        await tester.runAsync(() async {
          final image = await (tester.renderObject(
            find.byKey(capture),
          ) as RenderRepaintBoundary).toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(out).create(recursive: true);
          await File('$out/${entry.key}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
