import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/screens/source_diagnostics_page.dart';
import 'package:yazhal/services/settings_manager.dart';
import 'package:yazhal/services/source_diagnostics.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dir = await Directory.systemTemp.createTemp('yazhal_diag_ui');
    Hive.init(dir.path);
    for (final b in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(b);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  setUp(() {
    offlineMode.value = false;
  });
  SourceDiagnosticReport report() => SourceDiagnosticReport(
    'The API is returning HTML on this connection.',
    const [
      SourceCheck(
        'DNS',
        'passed',
        '2 public addresses; addresses not recorded.',
      ),
      SourceCheck(
        'Direct search API',
        'failed',
        'HTTP 200; text/html; site_unavailable',
      ),
      SourceCheck('Installed adapter', 'failed', 'provider_unavailable'),
    ],
    '1.0.10',
  );
  testWidgets(
    'diagnostic check runs only when requested and offers a copyable safe report',
    (tester) async {
      var calls = 0;
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData')
              copied = (call.arguments as Map)['text'] as String;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SourceDiagnosticsPage(
            runCheck: () async {
              calls++;
              return report();
            },
          ),
        ),
      );
      expect(calls, 0);
      await tester.tap(find.text('Run source check'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Direct search API · failed'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Copy diagnostic report'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy diagnostic report'));
      await tester.pumpAndSettle();
      expect(copied, contains('HTTP 200'));
      expect(copied, isNot(contains('<html>')));
    },
  );
  testWidgets('offline mode avoids diagnostic network activity', (
    tester,
  ) async {
    offlineMode.value = true;
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SourceDiagnosticsPage(
          runCheck: () async {
            calls++;
            return report();
          },
        ),
      ),
    );
    await tester.tap(find.text('Run source check'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('Turn off offline mode'), findsOneWidget);
  });
  testWidgets(
    'diagnostic results fit narrow screens with enlarged text and failure details stay sanitized',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: SourceDiagnosticsPage(runCheck: () async => report()),
        ),
      );
      await tester.tap(find.text('Run source check'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Copy diagnostic report'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
