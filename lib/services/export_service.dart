import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/tax_record.dart';

class ExportService {
  String buildCsv(List<TaxRecord> records) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Property,Financial Year,Income,Expenses,Net Position,Locked,Notes,Source File',
    );
    for (final record in records) {
      buffer.writeln(
        [
          _escape(record.propertyName),
          _escape(record.financialYear),
          record.totalIncome.toStringAsFixed(2),
          record.totalExpenses.toStringAsFixed(2),
          record.netPosition.toStringAsFixed(2),
          record.isLocked ? 'Yes' : 'No',
          _escape(record.notes),
          _escape(record.sourceFileName ?? ''),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  Uint8List buildSummaryPdf(List<TaxRecord> records, {String? title}) {
    final document = PdfDocument();
    final page = document.pages.add();
    final graphics = page.graphics;
    final headingFont = PdfStandardFont(PdfFontFamily.helvetica, 18);
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 11);

    graphics.drawString(
      title ?? 'Tax Summary Report',
      headingFont,
      bounds: const Rect.fromLTWH(0, 0, 500, 24),
    );

    double y = 36;
    final sorted = [...records]
      ..sort((a, b) => a.financialYear.compareTo(b.financialYear));
    for (final record in sorted) {
      final sign = record.netPosition >= 0 ? 'Positive' : 'Negative';
      final lines = [
        'Property: ${record.propertyName}',
        'FY: ${record.financialYear}',
        'Income: \$${record.totalIncome.toStringAsFixed(2)}',
        'Expenses: \$${record.totalExpenses.toStringAsFixed(2)}',
        'Net Position: \$${record.netPosition.toStringAsFixed(2)} ($sign)',
      ];
      for (final line in lines) {
        graphics.drawString(
          line,
          bodyFont,
          bounds: Rect.fromLTWH(0, y, 520, 16),
        );
        y += 15;
      }
      y += 8;
      if (y > 740) {
        y = 20;
        final nextPage = document.pages.add();
        nextPage.graphics.drawString(
          title ?? 'Tax Summary Report (cont.)',
          headingFont,
          bounds: const Rect.fromLTWH(0, 0, 500, 24),
        );
      }
    }

    final bytes = document.saveSync();
    document.dispose();
    return Uint8List.fromList(bytes);
  }

  String buildExcelFriendlyContent(List<TaxRecord> records) {
    return const Utf8Codec().decode(
      const Utf8Codec().encode(buildCsv(records)),
    );
  }

  String _escape(String value) {
    final sanitized = value.replaceAll('"', '""');
    return '"$sanitized"';
  }
}
