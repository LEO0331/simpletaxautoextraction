import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/services/pdf_extraction_service.dart';

void main() {
  final configuredPath = Platform.environment['COMMSEC_SAMPLE_PDF_PATH'];
  final samplePath = configuredPath?.trim();

  test('parses CommSec sample PDF from local filesystem', () async {
    if (samplePath == null || samplePath.isEmpty) {
      print('Skipping: COMMSEC_SAMPLE_PDF_PATH is not set.');
      return;
    }

    final file = File(samplePath);
    if (!file.existsSync()) {
      print('Skipping: sample PDF not found at $samplePath');
      return;
    }

    final bytes = await file.readAsBytes();
    final service = PdfExtractionService();

    final result = await service.extractInvestmentTransactionFromPdf(
      bytes,
      sourceFileName: file.uri.pathSegments.isEmpty
          ? 'C173462109.pdf'
          : file.uri.pathSegments.last,
    );

    final draft = result.draft;
    expect(result.rawText.trim(), isNotEmpty);
    expect(draft.transactionType.name, anyOf('buy', 'sell'));
    expect(
      (draft.ticker.isNotEmpty) ||
          ((draft.units ?? 0) > 0) ||
          ((draft.totalCost ?? 0) > 0) ||
          (draft.confirmationNumber != null &&
              draft.confirmationNumber!.isNotEmpty),
      isTrue,
    );
    expect(result.confidence, inInclusiveRange(0.0, 1.0));
  });
}
