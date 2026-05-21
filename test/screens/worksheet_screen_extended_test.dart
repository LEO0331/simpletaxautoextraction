import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/screens/worksheet_screen.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';

class _NoopFirestoreService implements FirestoreService {
  bool shouldThrowOnSave = false;

  @override
  Future<void> saveTaxRecord(TaxRecord record) async {
    if (shouldThrowOnSave) {
      throw StateError('save failed');
    }
  }

  @override
  Future<SaveTaxRecordResult> saveTaxRecordWithStrategy(
    TaxRecord record, {
    bool saveAsNewYear = false,
    String? overrideFinancialYear,
  }) async {
    return SaveTaxRecordResult(
      documentId: 'copied-id',
      replacedExistingYear: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> setLargeTestSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('locked worksheet blocks direct save and displays line items', (
    tester,
  ) async {
    await setLargeTestSurface(tester);
    final record = TaxRecord.empty('u1', '2024-2025').copyWith(
      isLocked: true,
      lineItems: const [
        {
          'sourceCategory': 'Admin Fee',
          'mappedCategory': 'Property agent fees and commission',
          'amount': 55.0,
        },
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorksheetScreen(
          record: record,
          firestoreService: _NoopFirestoreService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Extracted Transaction Details'), findsOneWidget);
    expect(
      find.textContaining('Admin Fee -> Property agent fees and commission'),
      findsOneWidget,
    );

    final saveButton = find.text('Save Data');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('This record is locked'), findsOneWidget);

    final firstField = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );
    expect(firstField.enabled, isFalse);
  });

  testWidgets('save as new year validates input then saves copy', (
    tester,
  ) async {
    await setLargeTestSurface(tester);
    final service = _NoopFirestoreService();
    final record = TaxRecord.empty('u1', '2024-2025');
    await tester.pumpWidget(
      MaterialApp(
        home: WorksheetScreen(record: record, firestoreService: service),
      ),
    );
    await tester.pumpAndSettle();

    final copyButton = find.byIcon(Icons.content_copy);
    await tester.ensureVisible(copyButton);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();

    expect(find.text('Save As New Financial Year'), findsOneWidget);
    final yearField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(yearField, '2024');
    await tester.tap(find.text('Save Copy'));
    await tester.pumpAndSettle();

    expect(
      find.text('Use YYYY-YYYY and ensure end year is start+1.'),
      findsOneWidget,
    );

    await tester.enterText(yearField, '2025-2026');
    await tester.tap(find.text('Save Copy'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Saved as FY 2025-2026'), findsOneWidget);
  });

  testWidgets('save failure queues draft and shows retry action', (
    tester,
  ) async {
    await setLargeTestSurface(tester);
    final service = _NoopFirestoreService()..shouldThrowOnSave = true;
    final record = TaxRecord.empty('u1', '2024-2025');
    await tester.pumpWidget(
      MaterialApp(
        home: WorksheetScreen(record: record, firestoreService: service),
      ),
    );
    await tester.pumpAndSettle();

    final saveButton = find.byIcon(Icons.save);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Save failed, draft queued for sync'),
      findsOneWidget,
    );
    expect(find.text('Retry now'), findsOneWidget);
  });

  testWidgets('expense input updates totals while unlocked', (tester) async {
    await setLargeTestSurface(tester);
    final service = _NoopFirestoreService();
    final record = TaxRecord.empty('u1', '2024-2025');
    await tester.pumpWidget(
      MaterialApp(
        home: WorksheetScreen(record: record, firestoreService: service),
      ),
    );
    await tester.pumpAndSettle();

    final expenseField = find.descendant(
      of: find.widgetWithText(Row, 'Advertising for tenants'),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(expenseField, '120');
    await tester.pumpAndSettle();

    expect(find.text('\$120.00'), findsWidgets);
  });
}
