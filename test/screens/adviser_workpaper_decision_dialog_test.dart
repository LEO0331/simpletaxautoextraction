import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/screens/adviser_workpaper_decision_dialog.dart';

void main() {
  testWidgets(
    'standalone adviser dialog keeps controllers until exit completes',
    (tester) async {
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  await showAdviserWorkpaperDecisionDialog(
                    context,
                    yearStart: 2024,
                    scopeFingerprint: List.filled(64, 'a').join(),
                    categoryTotals: {},
                    issues: [],
                  );
                  completed = true;
                },
                child: const Text('Open adviser workpaper'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open adviser workpaper'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'Synthetic adviser');
      final dialogContext = tester.element(find.byType(AlertDialog));
      Navigator.of(dialogContext).pop();
      await tester.pump(const Duration(milliseconds: 10));
      expect(completed, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
