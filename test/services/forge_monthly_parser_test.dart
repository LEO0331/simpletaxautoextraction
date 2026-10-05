import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/services/pdf_extraction_service.dart';

String monthlyReport({
  bool splitNumbers = false,
  String compensation = 'Compensation',
}) {
  String row(String label, double annual) {
    final amounts = [
      annual.toStringAsFixed(2),
      ...List.filled(11, '0.00'),
      annual.toStringAsFixed(2),
    ];
    return '$label\n${amounts.join(splitNumbers ? '\n' : ' ')}';
  }

  return '''
Date 1/07/2025 to 30/06/2026
Jul Aug Sep Oct Nov Dec Jan Feb Mar Apr May Jun Total
Owner Contributions
0.00
Property Income
${row(compensation, 560)}
${row('Residential Rent', 32564.05)}
\$33,124.05
(GST Total: \$0.00)
Property Expenses
${row('Administration Fee (GST Inclusive)', 26.40)}
${row('General Repairs and Maintenance (GST Inclusive)', 4964.14)}
${row('Landlord Insurance (GST Inclusive)', 380)}
${row('Letting Fee (GST Inclusive)', 693.13)}
${row('Locks, Keys, Card Keys (GST Inclusive)', 66.76)}
${row('Residential Management Fee (GST Inclusive)', 1791.02)}
\$7,921.45
(GST Total: \$711.14)
PROPERTY BALANCE: \$25,202.60
Owner Payments
\$25,202.60
''';
}

void main() {
  final service = PdfExtractionService();
  for (final split in [false, true]) {
    test('monthly Forge totals reconcile with split numbers=$split', () {
      final result = service.parseExtractedTextWithMetadata(
        monthlyReport(splitNumbers: split),
        'test',
        '2025-2026',
      );
      expect(result.validationErrors, isEmpty);
      expect(result.isSafeToImport, isTrue);
      expect(result.detectedFinancialYear, '2025-2026');
      expect(result.record.income['Gross rent'], closeTo(32564.05, .001));
      expect(result.record.income['Other rental-related income'], 560);
      expect(result.record.totalIncome, closeTo(33124.05, .001));
      expect(
        result.record.expenses['Property agent fees and commission'],
        closeTo(2510.55, .001),
      );
      expect(
        result.record.expenses['Repairs and maintenance'],
        closeTo(4964.14, .001),
      );
      expect(result.record.expenses['Insurance'], 380);
      expect(result.unmappedEntries.single.amount, 66.76);
      expect(result.totalEntryCount, 8);
      expect(
        result.record.totalExpenses + result.unmappedEntries.single.amount,
        closeTo(7921.45, .001),
      );
    });
  }
  test('custom mappings reconcile unknown rows without adding GST twice', () {
    final result = service.parseExtractedTextWithMetadata(
      monthlyReport(),
      'test',
      '2025-2026',
      customExpenseMappings: {'locks': 'Repairs and maintenance'},
    );
    expect(result.validationErrors, isEmpty);
    expect(result.unmappedEntries, isEmpty);
    expect(result.record.totalExpenses, closeTo(7921.45, .001));
    expect(result.record.netPosition, closeTo(25202.60, .001));
  });
  test('rejects a wrong selected year', () {
    final result = service.parseExtractedTextWithMetadata(
      monthlyReport(),
      'test',
      '2026-2027',
    );
    expect(result.isSafeToImport, isFalse);
    expect(result.validationErrors.single, contains('2025-2026'));
    final corrected = result.withFinancialYear('2025-2026');
    expect(corrected.isSafeToImport, isTrue);
    expect(corrected.record.totalIncome, result.record.totalIncome);
    expect(result.record.financialYear, '2026-2027');
  });
  test('rejects monthly row with a wrong annual total', () {
    final result = service.parseExtractedTextWithMetadata(
      monthlyReport().replaceFirst('560.00 0.00', '561.00 0.00'),
      'test',
      '2025-2026',
    );
    expect(result.isSafeToImport, isFalse);
    expect(result.validationErrors, contains(contains('Monthly amounts')));
    final wrongYear = result.withFinancialYear('2026-2027');
    expect(wrongYear.withFinancialYear('2025-2026').isSafeToImport, isFalse);
  });
  test('rejects missing data and missing subtotals', () {
    final result = service.parseExtractedTextWithMetadata(
      monthlyReport()
          .replaceFirst(
            'Residential Rent',
            'Residential Rent\nUnexpected category',
          )
          .replaceFirst('32564.05 0.00', '0.00')
          .replaceFirst('\$7,921.45', ''),
      'test',
      '2025-2026',
    );
    expect(result.isSafeToImport, isFalse);
    expect(result.validationErrors, isNotEmpty);
    expect(
      service
          .parseExtractedTextWithMetadata('', 'test', '2025-2026')
          .isSafeToImport,
      isFalse,
    );
  });
  test('unknown income is retained for review', () {
    final result = service.parseExtractedTextWithMetadata(
      monthlyReport(compensation: 'Unusual receipt'),
      'test',
      '2025-2026',
    );
    expect(result.validationErrors, isEmpty);
    expect(
      result.unmappedEntries.where((entry) => entry.isIncome).single.amount,
      560,
    );
  });
  test('invalid stored custom mappings produce reviewable entries', () {
    final result = service.parseExtractedTextWithMetadata(
      monthlyReport(),
      'test',
      '2025-2026',
      customIncomeMappings: {'rent': 'Insurance'},
      customExpenseMappings: {'locks': 'Nonexistent category'},
    );
    expect(result.record.income['Gross rent'], 0);
    expect(result.record.income.containsKey('Insurance'), isFalse);
    expect(result.record.expenses.containsKey('Nonexistent category'), isFalse);
    expect(
      result.unmappedEntries.where((entry) => entry.isIncome).single.amount,
      32564.05,
    );
    expect(result.validationErrors, isEmpty);
  });
}
