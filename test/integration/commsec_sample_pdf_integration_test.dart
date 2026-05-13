import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/services/pdf_extraction_service.dart';

void main() {
  final configuredPath = Platform.environment['COMMSEC_SAMPLE_PDF_PATH'];
  final samplePath = configuredPath?.trim();

  test('parses CommSec sample PDF from local filesystem', () async {
    if (samplePath == null || samplePath.isEmpty) {
      debugPrint('Skipping: COMMSEC_SAMPLE_PDF_PATH is not set.');
      return;
    }

    final file = File(samplePath);
    if (!file.existsSync()) {
      debugPrint('Skipping: sample PDF not found at $samplePath');
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
    if (Platform.environment['COMMSEC_DEBUG_STRUCTURE'] == '1') {
      _debugRedactedStructure(result.rawText);
    }

    final draft = result.draft;
    expect(result.rawText.trim(), isNotEmpty);
    expect(draft.securityName, 'BETASHARES NASDAQ 100 ETF');
    expect(draft.ticker, 'NDQ');
    expect(draft.transactionType.name, 'buy');
    expect(draft.tradeDate, DateTime(2026, 3, 30));
    expect(draft.settlementDate, DateTime(2026, 4, 1));
    expect(draft.units, closeTo(80, 0.0001));
    expect(draft.averagePrice, closeTo(49.66, 0.0001));
    expect(draft.consideration, closeTo(3972.80, 0.0001));
    expect(draft.brokerage, closeTo(7.94, 0.0001));
    expect(draft.gst, closeTo(0.72, 0.0001));
    expect(draft.totalCost, closeTo(3980.74, 0.0001));
    expect(draft.confirmationNumber, isNotEmpty);
    expect(draft.accountNumber, isNotEmpty);
    expect(result.missingFields, isEmpty);
    expect(result.confidence, 1.0);
  });
}

void _debugRedactedStructure(String rawText) {
  final labels = RegExp(
    r'(security|company|buy|sell|date|settlement|units|consideration|brokerage|gst|total|average|confirmation|account|contract)',
    caseSensitive: false,
  );
  final lines = rawText
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final buffer = StringBuffer();
  buffer.writeln('FIRST_LINES');
  for (var i = 0; i < lines.length && i < 70; i++) {
    buffer.writeln('${i.toString().padLeft(2, '0')}: ${_redactLine(lines[i])}');
  }
  buffer.writeln('LABEL_CONTEXT');
  for (var i = 0; i < lines.length; i++) {
    if (!labels.hasMatch(lines[i])) {
      continue;
    }
    buffer.writeln(_redactLine(lines[i]));
    for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
      buffer.writeln('  ${_redactLine(lines[j])}');
    }
  }
  debugPrint(buffer.toString());
}

String _redactLine(String line) {
  return line
      .replaceAll(RegExp(r'\bMR\b.*', caseSensitive: false), '[name]')
      .replaceAll(RegExp(r'\b\d{5,}\b'), '[number]')
      .replaceAll(RegExp(r'\b[A-Z]\d{6,}\b'), '[id]')
      .replaceAll(RegExp(r'\$?\d{1,3}(?:,\d{3})*(?:\.\d+)?'), '[amount]');
}
