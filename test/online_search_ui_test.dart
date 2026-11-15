import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/localization/app_localizations.dart';
import 'package:yazhal/screens/extension_search_page.dart';
import 'package:yazhal/services/bundled_providers.dart';
import 'package:yazhal/services/extensions/extension_package.dart';
import 'package:yazhal/services/extensions/native_extension_service.dart';
import 'package:yazhal/services/io_service.dart';
import 'package:yazhal/services/provider_router.dart';
import 'package:yazhal/services/settings_manager.dart';
import 'package:yazhal/widgets/download_quality_dialog.dart';

Widget app(Widget page) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    fontFamily: Platform.environment['YAZHAL_TEST_FONT'] == null
        ? null
        : 'TestSans',
  ),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: page,
);
Map<String, dynamic> provider(String id, String name) => {
  'id': id,
  'name': name,
  'enabled': true,
  'manifest': {
    'type': ['metadata_provider', 'download_provider'],
  },
};
void main() {
  late Directory dir;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = Platform.environment['YAZHAL_TEST_FONT'];
    if (font != null)
      await (FontLoader('TestSans')..addFont(
            Future.value(ByteData.sublistView(await File(font).readAsBytes())),
          ))
          .load();
    final icons = Platform.environment['YAZHAL_TEST_ICONS'];
    if (icons != null)
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(await File(icons).readAsBytes())),
          ))
          .load();
    dir = await Directory.systemTemp.createTemp('yazhal_online_ui');
    applicationDirPath = dir.path;
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  setUp(() async {
    await Hive.box('settings').clear();
    offlineMode.value = false;
    await Hive.box('settings').put('javascriptExtensions', [
      provider('jiosaavn', 'JioSaavn'),
      provider('alternate', 'Alternate Music'),
    ]);
  });
  Future<void> pumpUntilVisible(WidgetTester tester, String text) async {
    for (var i = 0; i < 50 && find.text(text).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text(text), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'magale');
    await tester.tap(find.byTooltip('Search music'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'compact search bar defaults to JioSaavn and error offers retry and provider change without leaking stack or secrets',
    (tester) async {
      await tester.pumpWidget(
        app(
          ExtensionSearchPage(
            selectProvider: (_) async {},
            searchProvider: (_, __) async => throw StateError(
              'network_unreachable secret-token at __host (<eval>:5:128)',
            ),
          ),
        ),
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search source'), findsNothing);
      expect(find.byKey(const Key('search-provider-button')), findsOneWidget);
      expect(find.text('Searching JioSaavn'), findsOneWidget);
      await submit(tester);
      expect(
        find.textContaining('Could not connect to JioSaavn'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Change provider'), findsOneWidget);
      expect(find.textContaining('secret-token'), findsNothing);
      expect(find.textContaining('<eval>'), findsNothing);
    },
  );
  testWidgets(
    'changing provider preserves query and reruns it on the selected source',
    (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        app(
          ExtensionSearchPage(
            selectProvider: (_) async {},
            searchProvider: (id, q) async {
              calls.add('$id:$q');
              if (id == 'jiosaavn') throw StateError('provider_unavailable');
              return [];
            },
          ),
        ),
      );
      await submit(tester);
      await tester.tap(find.text('Change provider'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alternate Music'));
      await tester.pumpAndSettle();
      await pumpUntilVisible(tester, 'Searching Alternate Music');
      expect(calls, ['jiosaavn:magale', 'alternate:magale']);
      expect(find.text('Searching Alternate Music'), findsOneWidget);
      expect(
        find.text(
          'No songs found on Alternate Music. Try another search or provider.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets('changing source ignores an old pending response', (
    tester,
  ) async {
    final old = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(
      app(
        ExtensionSearchPage(
          selectProvider: (_) async {},
          searchProvider: (id, q) async => id == 'jiosaavn' ? old.future : [],
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'magale');
    await tester.tap(find.byTooltip('Search music'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('search-provider-button')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Alternate Music'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await pumpUntilVisible(tester, 'Searching Alternate Music');
    expect(find.byType(LinearProgressIndicator), findsNothing);
    old.complete([
      {'ytid': 'stale', 'title': 'Wrong old result'},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Wrong old result'), findsNothing);
    expect(find.text('Searching Alternate Music'), findsOneWidget);
  });
  testWidgets(
    'retry repeats original provider query; offline mode makes no request',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        app(
          ExtensionSearchPage(
            selectProvider: (_) async {},
            searchProvider: (_, __) async {
              calls++;
              throw StateError('provider_unavailable');
            },
          ),
        ),
      );
      await submit(tester);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      offlineMode.value = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.textContaining('Offline mode is on'), findsOneWidget);
    },
  );
  test('Live Music Archive requires explicit selection to enable and never takes the JioSaavn default silently', () async {
    expect(ProviderRouter.selected, 'jiosaavn');
    expect(
      ProviderRouter.searchable.any((p) => p['id'] == 'catalog:archive'),
      false,
    );
    await ProviderRouter.select('catalog:archive');
    expect(Hive.box('settings').get('archiveFlacEnabled'), true);
    expect(ProviderRouter.selected, 'catalog:archive');
  });
  testWidgets(
    'download quality shows each real bitrate and the actual source in brackets',
    (tester) async {
      await tester.runAsync(() async {
        final bytes = File('assets/providers/jiosaavn.sflx').readAsBytesSync();
        final package = ExtensionPackage.decode(
          'jiosaavn',
          bytes,
          BundledProviders.digest,
        );
        await NativeExtensionService.instance.install(
          package,
          bytes,
          repository: 'https://example.org/registry.json',
          downloadUrl: 'https://example.org/provider.sflx',
        );
        await NativeExtensionService.enable('jiosaavn', true);
      });
      String? selected;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await chooseDownloadQuality(context, {
                    'source': 'js-extension',
                    'extensionId': 'jiosaavn',
                  });
                },
                child: const Text('Download'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      await pumpUntilVisible(tester, 'AAC 320 kbps (JioSaavn)');
      expect(find.text('AAC 320 kbps (JioSaavn)'), findsOneWidget);
      expect(find.text('AAC 160 kbps (JioSaavn)'), findsOneWidget);
      await tester.tap(find.text('AAC 320 kbps (JioSaavn)'));
      await tester.pumpAndSettle();
      expect(selected, 'AAC_320');
    },
  );
  testWidgets('FLAC quality keeps catalogue attribution and original format', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await chooseDownloadQuality(context, {
                  'source': 'extension',
                  'extensionId': 'archive',
                });
              },
              child: const Text('Download'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.text('Original FLAC (Live Music Archive)'), findsOneWidget);
    await tester.tap(find.text('Original FLAC (Live Music Archive)'));
    await tester.pumpAndSettle();
    expect(selected, 'original');
  });
  testWidgets(
    'search error and provider picker fit a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const capture = Key('online-capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: app(
            MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 740),
                textScaler: TextScaler.linear(1.3),
              ),
              child: ExtensionSearchPage(
                selectProvider: (_) async {},
                searchProvider: (_, __) async =>
                    throw StateError('provider_unavailable'),
              ),
            ),
          ),
        ),
      );
      await submit(tester);
      expect(tester.takeException(), isNull);
      Future<void> captureImage(String name) async {
        final out = Platform.environment['YAZHAL_SEARCH_CAPTURE_DIR'];
        if (out == null) return;
        await tester.runAsync(() async {
          final image = await (tester.renderObject(
            find.byKey(capture),
          ) as RenderRepaintBoundary).toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(out).create(recursive: true);
          await File('$out/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await captureImage('search-error');
      await tester.tap(find.text('Change provider'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureImage('provider-picker');
    },
  );
}
