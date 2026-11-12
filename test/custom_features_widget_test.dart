import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/localization/app_localizations.dart';
import 'package:yazhal/widgets/refreshable_recommendations.dart';
import 'package:yazhal/widgets/song_bar.dart';
import 'package:yazhal/widgets/song_selection_region.dart';

Widget app(Widget body) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: body),
);

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('yazhal_widgets');
    Hive.init(dir.path);
    for (final name in ['user', 'userNoBackup', 'settings', 'cache']) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets('long press selects a row; selection taps do not play music', (
    tester,
  ) async {
    final song = {'ytid': 'local:one', 'title': 'One', 'artist': ''};
    var played = 0;
    await tester.pumpWidget(
      app(
        SongSelectionRegion(
          songs: [song],
          child: ListView(
            children: [SongBar(song, true, onPlay: () => played++)],
          ),
        ),
      ),
    );
    await tester.longPress(find.text('One'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.text('One'));
    await tester.pump();
    expect(find.text('0 selected'), findsOneWidget);
    expect(played, 0);
    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pump();
    await tester.tap(find.text('One'));
    expect(played, 1);
  });

  testWidgets(
    'select all covers displayed rows; filter changes clear hidden selections',
    (tester) async {
      final a = {'ytid': 'a', 'title': 'A'};
      final b = {'ytid': 'b', 'title': 'B'};
      var filtered = false;
      late StateSetter redraw;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) {
              redraw = setState;
              return SongSelectionRegion(
                songs: filtered ? [a] : [a, b],
                filter: filtered ? 'A' : '',
                child: const SizedBox(),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Select songs'));
      await tester.pump();
      await tester.tap(find.byTooltip('Select all visible'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      redraw(() => filtered = true);
      await tester.pump();
      expect(find.text('Select songs'), findsOneWidget);
      expect(find.text('2 selected'), findsNothing);
      // Externally owned lists have no removal button.
      await tester.tap(find.text('Select songs'));
      await tester.pump();
      expect(find.byTooltip('Remove from playlist'), findsNothing);
    },
  );

  testWidgets('bulk removal confirms count and keeps audio semantics explicit', (
    tester,
  ) async {
    final song = {'ytid': 'a', 'title': 'A'};
    List<Map>? removed;
    await tester.pumpWidget(
      app(
        SongSelectionRegion(
          songs: [song],
          onRemove: (songs) async {
            removed = songs;
          },
          child: const SizedBox(),
        ),
      ),
    );
    await tester.tap(find.text('Select songs'));
    await tester.pump();
    await tester.tap(find.byTooltip('Select all visible'));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove from playlist'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Remove 1 selected songs from this playlist? Audio files will be kept.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Remove from playlist'));
    await tester.pumpAndSettle();
    expect(removed, [song]);
    expect(find.text('Select songs'), findsOneWidget);
  });

  testWidgets(
    'empty recommendation results retain an enabled refresh control',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        app(
          RefreshableRecommendations(
            title: 'Suggestions',
            scope: 'test',
            load: (_, __) async {
              calls++;
              return [];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No new recommendations available. Try again later.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Refresh recommendations'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    },
  );
}
