import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yazhal/widgets/download_quality_dialog.dart';

void main() {
  testWidgets(
    'download chooser returns the selected quality without relabelling it',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await chooseDownloadQuality(context, {
                    'ytid': 'youtube-track',
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
      expect(find.text('Download quality'), findsOneWidget);
      expect(find.textContaining('High ·'), findsOneWidget);
      expect(find.textContaining('Low ·'), findsOneWidget);
      await tester.tap(find.textContaining('Low ·'));
      await tester.pumpAndSettle();
      expect(selected, 'low');
    },
  );
}
