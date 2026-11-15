import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/screens/music_sources_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('yazhal_sources_ui');
    Hive.init(dir.path);
    for (final box in ['settings', 'cache', 'user', 'userNoBackup']) {
      await Hive.openBox(box);
    }
    await Hive.box('settings').put('javascriptExtensions', [
      {
        'id': 'jiosaavn',
        'name': 'JioSaavn',
        'version': '1.0.10',
        'author': 'HemanthJabalpuri; Mornye compatibility fixes',
        'enabled': true,
        'manifest': {
          'type': ['metadata_provider', 'download_provider'],
        },
      },
    ]);
    await Hive.box('settings').put('lyricsExtension', 'jiosaavn');
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  testWidgets(
    'source manager fits a phone and recovers a stale lyrics preference',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const capture = Key('source-screen');
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            theme: ThemeData(colorSchemeSeed: const Color(0xff17616b)),
            home: const MusicSourcesPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your music, your sources'), findsOneWidget);
      expect(find.text('Music sources'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['YAZHAL_UI_SCREENSHOT'];
      if (output != null) {
        await tester.runAsync(() async {
          final image = await (tester.renderObject(
            find.byKey(capture),
          ) as RenderRepaintBoundary).toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(output).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
}
