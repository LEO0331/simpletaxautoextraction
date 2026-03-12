import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/screens/worksheet_screen.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';

class MockFirestoreService implements FirestoreService {
  bool isSaved = false;
  TaxRecord? savedRecord;

  @override
  Future<void> saveTaxRecord(TaxRecord record) async {
    isSaved = true;
    savedRecord = record;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget buildApp(TaxRecord record, FirestoreService firestoreService) {
    return MaterialApp(
      home: WorksheetScreen(
        record: record,
        firestoreService: firestoreService,
      ),
    );
  }

  testWidgets('WorksheetScreen displays total income and expenses correctly', (WidgetTester tester) async {
    final record = TaxRecord(
      userId: 'user1',
      financialYear: '2024-2025',
      income: {'Gross rent': 1000.0},
      expenses: {'Water charges': 200.0},
    );
    final mockFirestore = MockFirestoreService();

    await tester.pumpWidget(buildApp(record, mockFirestore));
    await tester.pumpAndSettle();

    expect(find.text('\$1000.00'), findsOneWidget); // Total Income
    expect(find.text('\$200.00'), findsOneWidget); // Total Expenses
    expect(find.text('\$800.00'), findsOneWidget); // Net Position
  });

  testWidgets('WorksheetScreen updates total when input changes', (WidgetTester tester) async {
    final record = TaxRecord.empty('user1', '2024-2025');
    final mockFirestore = MockFirestoreService();

    await tester.pumpWidget(buildApp(record, mockFirestore));
    await tester.pumpAndSettle();

    final rentField = find.descendant(
      of: find.widgetWithText(Row, 'Gross rent').first,
      matching: find.byType(TextFormField),
    );

    await tester.enterText(rentField, '500');
    await tester.pumpAndSettle();

    expect(find.text('\$500.00'), findsWidgets); // Updated text field value AND the summary
  });

  testWidgets('WorksheetScreen saves record when Save Data is pressed', (WidgetTester tester) async {
    final record = TaxRecord.empty('user1', '2024-2025');
    final mockFirestore = MockFirestoreService();

    await tester.pumpWidget(buildApp(record, mockFirestore));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Data'));
    await tester.pumpAndSettle();

    expect(mockFirestore.isSaved, isTrue);
  });
}
