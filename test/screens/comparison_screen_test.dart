import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/screens/comparison_screen.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';

class MockFirestoreService implements FirestoreService {
  final List<TaxRecord> records;

  MockFirestoreService(this.records);

  @override
  Stream<List<TaxRecord>> getUserTaxRecords(String userId) {
    return Stream.value(records);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('ComparisonScreen shows no data when records are empty', (WidgetTester tester) async {
    final mockService = MockFirestoreService([]);
    
    await tester.pumpWidget(MaterialApp(
      home: ComparisonScreen(
        firestoreService: mockService,
        userId: 'test_user',
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('No data available for comparison.'), findsOneWidget);
  });

  testWidgets('ComparisonScreen renders chart when data is available', (WidgetTester tester) async {
    final records = [
      TaxRecord(
        userId: 'test_user',
        financialYear: '2023-2024',
        income: {'Gross rent': 10000.0},
        expenses: {'Water charges': 1000.0},
      ),
      TaxRecord(
        userId: 'test_user',
        financialYear: '2024-2025',
        income: {'Gross rent': 12000.0},
        expenses: {'Water charges': 1500.0},
      ),
    ];
    
    final mockService = MockFirestoreService(records);
    
    await tester.pumpWidget(MaterialApp(
      home: ComparisonScreen(
        firestoreService: mockService,
        userId: 'test_user',
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.byType(BarChart), findsOneWidget);
    expect(find.text('Income vs Expenses vs Net Position'), findsOneWidget);
  });
}
