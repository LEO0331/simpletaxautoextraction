import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/services/pdf_extraction_service.dart';

void main() {
  group('PdfExtractionService metadata parsing', () {
    late PdfExtractionService service;

    setUp(() {
      service = PdfExtractionService();
    });

    test('applies custom mappings and records line items metadata', () {
      const text = '''
Property Expenses
Strata Levy
\$0.00
\$420.00
\$420.00
PROPERTY BALANCE:
''';

      final result = service.parseExtractedTextWithMetadata(
        text,
        'u1',
        '2024-2025',
        customExpenseMappings: {'strata': 'Body corporate fees and charges'},
        sourceFileName: 'statement.pdf',
      );

      expect(result.record.expenses['Body corporate fees and charges'], 420.0);
      expect(result.record.sourceFileName, 'statement.pdf');
      expect(result.record.sourceParser, isNotEmpty);
      expect(result.record.parserVersion, 'v2');
      expect(result.record.lineItems, isNotEmpty);
      expect(result.confidence, closeTo(1, 0.001));
    });

    test('tracks unmapped entries when keepUnknownAsSundry is false', () {
      const text = '''
Property Expenses
Something Totally Unknown
\$0.00
\$99.00
\$99.00
PROPERTY BALANCE:
''';

      final result = service.parseExtractedTextWithMetadata(
        text,
        'u1',
        '2024-2025',
        keepUnknownAsSundry: false,
      );

      expect(result.unmappedEntries.length, 1);
      expect(result.unmappedEntries.first.sourceCategory, contains('Unknown'));
    });
  });
}
