import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/services/pdf_extraction_service.dart';

void main() {
  final path = Platform.environment['FORGE_MONTHLY_SAMPLE_PDF_PATH'];
  test(
    'reads local FY2025-2026 monthly Forge PDF with the production extractor',
    () async {
      final result = await PdfExtractionService().extractPreviewFromPdf(
        await File(path!).readAsBytes(),
        'local-test',
        '2025-2026',
      );
      expect(result.validationErrors, isEmpty);
      expect(result.isSafeToImport, isTrue);
      expect(result.detectedFinancialYear, '2025-2026');
      expect(result.record.income['Gross rent'], closeTo(32564.05, .001));
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
      expect(
        result.record.totalExpenses + result.unmappedEntries.single.amount,
        closeTo(7921.45, .001),
      );
      expect(result.totalEntryCount, 8);
    },
    skip: path == null || path.isEmpty
        ? 'Set FORGE_MONTHLY_SAMPLE_PDF_PATH to a private local report.'
        : false,
  );
}
