import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/screens/worksheet_screen.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';

class _NoopFirestoreService implements FirestoreService {
  @override
  Future<void> saveTaxRecord(TaxRecord record) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('locked worksheet blocks direct save and displays line items', (
    tester,
  ) async {
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

    await tester.tap(find.text('Save Data'));
    await tester.pumpAndSettle();

    expect(find.textContaining('This record is locked'), findsOneWidget);

    final firstField = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );
    expect(firstField.enabled, isFalse);
  });
}
