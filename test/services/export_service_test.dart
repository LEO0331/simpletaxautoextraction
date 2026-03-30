import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/services/export_service.dart';

void main() {
  group('ExportService', () {
    final service = ExportService();
    final records = [
      TaxRecord(
        userId: 'u1',
        financialYear: '2023-2024',
        propertyName: 'Unit A',
        income: {'Gross rent': 10000},
        expenses: {'Water charges': 2500},
        notes: 'sample note',
      ),
      TaxRecord(
        userId: 'u1',
        financialYear: '2024-2025',
        propertyName: 'Unit A',
        income: {'Gross rent': 11000},
        expenses: {'Water charges': 2200},
      ),
    ];

    test('buildCsv includes headers and values', () {
      final csv = service.buildCsv(records);
      expect(csv, contains('Property,Financial Year,Income'));
      expect(csv, contains('"Unit A"'));
      expect(csv, contains('10000.00'));
      expect(csv.split('\n').length, greaterThan(2));
    });

    test('buildExcelFriendlyContent mirrors CSV content', () {
      final excel = service.buildExcelFriendlyContent(records);
      expect(excel, contains('Financial Year'));
      expect(excel, contains('2024-2025'));
    });

    test('buildSummaryPdf returns non-empty bytes', () {
      final bytes = service.buildSummaryPdf(records, title: 'Report');
      expect(bytes.length, greaterThan(100));
    });
  });
}
