import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:simpletaxautoextraction/models/tax_workspace.dart';
import 'package:simpletaxautoextraction/services/tax_workspace_calculator.dart';
import 'package:simpletaxautoextraction/services/tax_workspace_coordinator.dart';
import 'package:simpletaxautoextraction/services/accountant_workpaper_export.dart';

void main() {
  TaxWorkspaceBundle bundle() {
    final workspace = TaxWorkspace(userId: 'synthetic-owner', yearStart: 2024);
    final report = TaxWorkspaceReport(
      categoryTotals: {'salary': '123.45'},
      issues: ['Verify synthetic source'],
      sectionIssues: {},
      contributions: [
        {'source': '=unsafe, "formula"', 'amount': '123.45'},
      ],
      i1Scenarios: [],
      sourceFingerprint: 'synthetic-fingerprint',
      canFinalise: false,
    );
    return TaxWorkspaceBundle(
      workspace: workspace,
      items: [],
      rentals: [],
      fundStatements: [],
      cgtSnapshots: [],
      report: report,
      workspaceGeneration: 1,
      investmentGeneration: 1,
      investmentHistoryStart: null,
      hasCapitalActivity: false,
      investmentIssues: [],
      auditSources: {
        'transactions': [
          for (var i = 0; i < 180; i++)
            {'id': 'synthetic-$i', 'reference': 'Source evidence $i'},
        ],
      },
    );
  }

  test(
    'CSV includes issues, exact totals and every evidence row with safe quoting',
    () {
      final text = AccountantWorkpaperExport().csv(bundle());
      expect(text, contains('123.45'));
      expect(text, contains('Verify synthetic source'));
      expect(text, contains('"\'=unsafe, ""formula"""'));
      expect(text, contains('Source evidence 179'));
      expect(text, contains('synthetic-fingerprint'));
    },
  );
  test(
    'PDF pages preserve late evidence and review status without clipping',
    () {
      final bytes = AccountantWorkpaperExport().pdf(bundle());
      final document = PdfDocument(inputBytes: bytes);
      try {
        expect(document.pages.count, greaterThan(1));
        final text = PdfTextExtractor(document).extractText();
        expect(text, contains('Source evidence 179'));
        expect(text, contains('Review workpaper only'));
        expect(text, contains('Verify synthetic source'));
      } finally {
        document.dispose();
      }
    },
  );
}
