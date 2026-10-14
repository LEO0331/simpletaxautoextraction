import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'tax_workspace_coordinator.dart';

/// Portable workpapers, with every contribution and source included for review.
/// Exports remain local; neither a lodged return nor a liability assessment.
class AccountantWorkpaperExport {
  List<List<String>> rows(TaxWorkspaceBundle bundle) {
    final report = bundle.report;
    return [
      ['Section', 'Reference', 'Field', 'Value'],
      [
        'Review',
        'Status',
        'notice',
        'Review workpaper only; verify evidence and tax treatment before lodging.',
      ],
      [
        'Review',
        'Workspace',
        'financialYear',
        '${bundle.workspace.yearStart}-${bundle.workspace.yearStart + 1}',
      ],
      ['Review', 'Workspace', 'status', bundle.workspace.status],
      ['Review', 'Workspace', 'canFinalise', '${report.canFinalise}'],
      ['Review', 'Sources', 'fingerprint', report.sourceFingerprint],
      for (final issue in report.issues) ['Review issue', '', '', issue],
      for (final entry in report.categoryTotals.entries)
        ['Totals', entry.key, 'amount AUD', entry.value],
      ..._flatten('Workspace', bundle.workspace.toMap()),
      ..._flatten('Contributions', report.contributions),
      ..._flatten('I1 scenarios', report.i1Scenarios),
      ..._flatten('Evidence', bundle.auditSources),
    ];
  }

  String csv(TaxWorkspaceBundle bundle) =>
      rows(bundle).map((row) => row.map(_cell).join(',')).join('\r\n');

  Uint8List pdf(TaxWorkspaceBundle bundle) {
    final document = PdfDocument();
    final font = PdfStandardFont(PdfFontFamily.helvetica, 9);
    final heading = PdfStandardFont(PdfFontFamily.helvetica, 15);
    var page = document.pages.add();
    var size = page.getClientSize();
    var y = 0.0;
    void newPage() {
      page = document.pages.add();
      size = page.getClientSize();
      y = 0;
    }

    void write(String text, PdfFont currentFont) {
      // Measure actual wrapping before pagination; never reuse a prior page's graphics.
      final height = currentFont
          .measureString(text, layoutArea: Size(size.width, double.infinity))
          .height;
      if (y + height + 8 > size.height) newPage();
      if (height + 8 > size.height) {
        // Large evidence strings are split at bounded line lengths to avoid clipping.
        for (var start = 0; start < text.length; start += 90) {
          final end = start + 90 < text.length ? start + 90 : text.length;
          write(text.substring(start, end), currentFont);
        }
        return;
      }
      page.graphics.drawString(
        text,
        currentFont,
        bounds: Rect.fromLTWH(0, y, size.width, height + 2),
      );
      y += height + 6;
    }

    try {
      write('Australian tax review workpaper', heading);
      for (final row in rows(bundle).skip(1)) {
        write(row.where((v) => v.isNotEmpty).join(' | '), font);
      }
      return Uint8List.fromList(document.saveSync());
    } finally {
      document.dispose();
    }
  }

  static String _cell(String value) {
    // Prevent spreadsheet formula execution for account references and document text.
    final safe = RegExp(r'^\s*[=+@-]').hasMatch(value) ? "'$value" : value;
    return '"${safe.replaceAll('"', '""')}"';
  }

  static List<List<String>> _flatten(
    String section,
    dynamic value, [
    String path = '',
  ]) {
    if (value is Map) {
      return [
        for (final entry in value.entries)
          ..._flatten(
            section,
            entry.value,
            path.isEmpty ? '${entry.key}' : '$path.${entry.key}',
          ),
      ];
    }
    if (value is List) {
      return [
        for (var index = 0; index < value.length; index++)
          ..._flatten(section, value[index], '$path[$index]'),
      ];
    }
    return [
      [
        section,
        path,
        '',
        value == null
            ? ''
            : value is String
            ? value
            : jsonEncode(value),
      ],
    ];
  }
}
