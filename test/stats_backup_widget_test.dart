import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/localization/app_localizations.dart';
import 'package:yazhal/screens/settings_page.dart';
import 'package:yazhal/screens/stats_backup_page.dart';
import 'package:yazhal/services/settings_manager.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('yazhal_backup_ui');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  for (final offline in [true, false]) {
    testWidgets('statistics backup opens when offline mode is $offline', (
      tester,
    ) async {
      offlineMode.value = offline;
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(),
        ),
      );
      await tester.pumpAndSettle();
      final backup = find.text('Local statistics backup');
      expect(backup, findsOneWidget);
      await tester.ensureVisible(backup);
      await tester.pumpAndSettle();
      await tester.tap(backup);
      await tester.pumpAndSettle();
      expect(find.byType(StatsBackupPage), findsOneWidget);
      expect(find.text('Export backup file'), findsOneWidget);
      expect(find.text('Share backup file'), findsOneWidget);
      expect(find.text('Restore from file'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'export labels the portable file as JSON for the Android restore picker',
    (tester) async {
      final original = FilePickerPlatform.instance;
      final picker = _CapturingPicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = original);
      await tester.pumpWidget(const MaterialApp(home: StatsBackupPage()));
      await tester.tap(find.text('Export backup file'));
      await tester.pumpAndSettle();
      expect(picker.mime, 'application/json');
      expect(picker.name, endsWith('.json'));
      expect(
        jsonDecode(utf8.decode(picker.bytes!))['format'],
        'yazhal-stats-backup',
      );
      expect(find.text('Statistics backup exported.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _CapturingPicker extends FilePickerPlatform {
  String? mime;
  String? name;
  Uint8List? bytes;
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    mime = mimeType;
    name = fileName;
    this.bytes = bytes;
    return Uri.file('/test/$fileName');
  }
}
