import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/localization/app_localizations.dart';
import 'package:yazhal/screens/about_page.dart';
import 'package:yazhal/screens/flac_extensions_page.dart';
import 'package:yazhal/screens/local_music_page.dart';
import 'package:yazhal/services/common_services.dart';
import 'package:yazhal/widgets/fast_scroll.dart';

Widget app(Widget page) => RepaintBoundary(
  key: const ValueKey('preview'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: Platform.environment['YAZHAL_PREVIEW_FONT'] == null
        ? null
        : ThemeData(fontFamily: 'PreviewSans'),
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: page,
  ),
);
Future<void> preparePreview(WidgetTester tester) async {
  if (Platform.environment['YAZHAL_PREVIEW_DIR'] == null) return;
  await tester.binding.setSurfaceSize(const Size(412, 915));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> capture(WidgetTester tester, String name) async {
  final folder = Platform.environment['YAZHAL_PREVIEW_DIR'];
  if (folder == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('preview')),
    );
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(folder).create(recursive: true);
    await File('$folder/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  late Directory dir;
  setUpAll(() async {
    final font = Platform.environment['YAZHAL_PREVIEW_FONT'];
    if (font != null) {
      final loader = FontLoader('PreviewSans')
        ..addFont(
          Future.value(ByteData.sublistView(await File(font).readAsBytes())),
        );
      await loader.load();
      for (final style in ['Regular', 'Filled']) {
        await (FontLoader(
              'packages/fluentui_system_icons/FluentSystemIcons-$style',
            )..addFont(
              rootBundle.load(
                'packages/fluentui_system_icons/fonts/FluentSystemIcons-$style.ttf',
              ),
            ))
            .load();
      }
      await (FontLoader('paytoneOne')..addFont(
            rootBundle.load('assets/fonts/paytone/PaytoneOne-Regular.ttf'),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
    dir = await Directory.systemTemp.createTemp('yazhal_v2_widget');
    Hive.init(dir.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  testWidgets('scrollbar shares controller and drag moves a long list', (
    tester,
  ) async {
    late ScrollController controller;
    await preparePreview(tester);
    await tester.pumpWidget(
      app(
        FastScroll(
          builder: (c) {
            controller = c;
            return ListView.builder(
              controller: c,
              itemCount: 500,
              itemBuilder: (_, i) =>
                  SizedBox(height: 48, child: Text('Track $i')),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar)).controller,
      same(controller),
    );
    expect(tester.widget<Scrollbar>(find.byType(Scrollbar)).interactive, true);
    final rect = tester.getRect(find.byType(Scrollbar));
    await tester.dragFrom(
      Offset(rect.right - 4, rect.top + 10),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(500));
  });
  testWidgets('download destination opens directly in its settings tab', (
    tester,
  ) async {
    await preparePreview(tester);
    await tester.pumpWidget(app(const LocalMusicPage(initialTab: 2)));
    await tester.pumpAndSettle();
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Choose download folder'), findsOneWidget);
    await capture(tester, 'download-settings');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'metadata settings offer opt-in lookup and offline privacy controls',
    (tester) async {
      userOfflineSongs.value = [];
      await preparePreview(tester);
      await tester.pumpWidget(app(const LocalMusicPage(initialTab: 1)));
      await tester.pumpAndSettle();
      expect(find.text('Online metadata & artwork'), findsOneWidget);
      expect(find.text('Learn from offline listening'), findsOneWidget);
      expect(find.text('Clear offline listening history'), findsOneWidget);
      await capture(tester, 'metadata-settings');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'extension manager starts disabled and can enable built-in provider',
    (tester) async {
      await preparePreview(tester);
      await tester.pumpWidget(app(const FlacExtensionsPage()));
      await tester.pumpAndSettle();
      expect(find.text('Live Music Archive'), findsOneWidget);
      await capture(tester, 'flac-sources');
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      await tester.runAsync(() async {
        await tester.tap(find.byType(Switch));
        await Hive.box('settings').flush();
      });
      await tester.pumpAndSettle();
      expect(Hive.box('settings').get('archiveFlacEnabled'), true);
    },
  );
  testWidgets('about credits Yazhal maintainer and original project author', (
    tester,
  ) async {
    await preparePreview(tester);
    await tester.pumpWidget(app(const AboutPage()));
    await tester.pumpAndSettle();
    expect(find.text('Kausthuban R S'), findsOneWidget);
    expect(find.text('Based on Musify'), findsOneWidget);
    await capture(tester, 'about');
    expect(
      find.textContaining('Musify was originally created by Valeri Gokadze'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
