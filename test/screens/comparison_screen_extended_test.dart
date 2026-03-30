import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/screens/comparison_screen.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';

class _FirestoreWithRecords implements FirestoreService {
  _FirestoreWithRecords(this.records);

  final List<TaxRecord> records;

  @override
  Stream<List<TaxRecord>> getUserTaxRecords(String userId) =>
      Stream.value(records);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('shows anomaly alerts and property name in title', (
    tester,
  ) async {
    final service = _FirestoreWithRecords([
      TaxRecord(
        userId: 'u1',
        financialYear: '2023-2024',
        propertyId: 'p1',
        propertyName: 'Unit A',
        income: {'Gross rent': 10000},
        expenses: {'Water charges': 1000},
      ),
      TaxRecord(
        userId: 'u1',
        financialYear: '2024-2025',
        propertyId: 'p1',
        propertyName: 'Unit A',
        income: {'Gross rent': 14000},
        expenses: {'Water charges': 2000},
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: ComparisonScreen(
          firestoreService: service,
          userId: 'u1',
          propertyId: 'p1',
          propertyName: 'Unit A',
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.textContaining('Income vs Expenses vs Net Position (Unit A)'),
      findsOneWidget,
    );
    expect(find.text('Anomaly Alerts'), findsOneWidget);
    expect(find.textContaining('income changed'), findsOneWidget);
  });
}
