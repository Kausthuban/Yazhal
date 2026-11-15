import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/localization/app_localizations.dart';
import 'package:yazhal/screens/search_page.dart';
import 'package:yazhal/services/provider_router.dart';
import 'package:yazhal/services/settings_manager.dart';
import 'package:yazhal/services/youtube_search_provider.dart';
import 'package:yazhal/widgets/custom_search_bar.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class FakeVideo extends Fake implements Video {
  @override
  VideoId get id => VideoId('dQw4w9WgXcQ');
  @override
  String get title => 'Artist - Tamil Song (Official Audio)';
  @override
  String get author => 'Artist';
  @override
  ChannelId get channelId => ChannelId('UC38IQsAvIsxxjztdMZQtwHA');
  @override
  Duration? get duration => const Duration(seconds: 210);
  @override
  bool get isLive => false;
}

Widget app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);
void main() {
  late Directory dir;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dir = await Directory.systemTemp.createTemp('yazhal_restore');
    Hive.init(dir.path);
    for (final b in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(b);
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
      {
        'id': 'jiosaavn',
        'name': 'JioSaavn',
        'enabled': true,
        'manifest': {
          'type': ['metadata_provider', 'download_provider'],
        },
      },
    ]);
  });
  test('original YouTube search appears as an explicit selectable provider without overriding JioSaavn', () async {
    expect(
      ProviderRouter.available.any((p) => p['id'] == ProviderRouter.youtubeId),
      true,
    );
    expect(ProviderRouter.selected, 'jiosaavn');
    expect(ProviderRouter.youtubeEnabled, false);
    await ProviderRouter.select(ProviderRouter.youtubeId);
    expect(ProviderRouter.selected, ProviderRouter.youtubeId);
    expect(ProviderRouter.youtubeEnabled, true);
    expect(Hive.box('settings').get('youtubeSearchEnabled'), true);
    await ProviderRouter.select('jiosaavn');
    expect(ProviderRouter.youtubeAllowed, true);
    expect(ProviderRouter.youtubeEnabled, false);
    expect(ProviderRouter.selected, 'jiosaavn');
  });
  test('original song adapter preserves video identity, duration, title and playback compatibility without YouTube artwork', () async {
    String? requested;
    final adapter = YouTubeSearchProvider(
      searchVideos: (q) async {
        requested = q;
        return [FakeVideo()];
      },
    );
    final result = await adapter.search('  tamil song  ');
    expect(requested, 'tamil song');
    expect(result.single['ytid'], 'dQw4w9WgXcQ');
    expect(result.single['title'], 'Tamil Song');
    expect(result.single['artist'], 'Artist');
    expect(result.single['duration'], 210);
    expect(result.single['source'], 'youtube');
    expect(result.single['highResImage'], '');
    expect(result.single.containsKey('extensionId'), false);
  });
  test('empty YouTube query avoids the network and source errors propagate to the unified error UI', () async {
    var called = false;
    final adapter = YouTubeSearchProvider(
      searchVideos: (_) async {
        called = true;
        throw StateError('provider error');
      },
    );
    expect(await adapter.search('  '), isEmpty);
    expect(called, false);
    await expectLater(adapter.search('song'), throwsStateError);
  });
  testWidgets(
    'enabling YouTube no longer hides the unified provider selector',
    (tester) async {
      await tester.runAsync(() async {
        await ProviderRouter.select(ProviderRouter.youtubeId);
      });
      await tester.pumpWidget(app(const SearchPage()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('search-provider-button')), findsOneWidget);
      expect(find.text('Searching YouTube (Musify)'), findsOneWidget);
      expect(find.text('Classic Musify search'), findsOneWidget);
      await tester.tap(find.text('Classic Musify search'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomSearchBar), findsOneWidget);
    },
  );
  testWidgets(
    'classic online search honors offline mode before submitting requests',
    (tester) async {
      await tester.runAsync(() async {
        await ProviderRouter.select(ProviderRouter.youtubeId);
      });
      offlineMode.value = true;
      await tester.pumpWidget(app(const SearchPage(classic: true)));
      await tester.enterText(find.byType(TextField).first, 'offline query');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(
        find.text('Turn off offline mode to search online.'),
        findsOneWidget,
      );
    },
  );
}
