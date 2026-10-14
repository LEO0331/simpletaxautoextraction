import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:simpletaxautoextraction/services/managed_fund_pdf_service.dart';
import 'package:simpletaxautoextraction/services/parsers/managed_fund_statement_parser.dart';

FundPdfRow row(String label, [String? value, double column = .90]) =>
    FundPdfRow(1, label, [if (value != null) FundPdfAmount(value, column)]);
List<FundPdfRow> fixture({String issuer = 'Betashares'}) => [
  row(issuer),
  row(
    'Attribution Managed Investment Trust Member Annual Statement for year ended 30 June 2025',
  ),
  row('ASX code: SYN'),
  row('Account number: SYNTHETIC-ACCOUNT'),
  row('Part A: Summary of tax return items'),
  row('Total current year capital gains 18H', '220.00'),
  row('Capital gains - Discounted method (grossed up amount)', '200.00'),
  row('Capital gains - Other method', '20.00'),
  row('Assessable foreign source income 20E', '30.00'),
  row('Foreign income tax offset 20O', '4.00'),
  row('Part B: Components of attribution'),
  row('Gross cash distribution', '80.00'),
  row('AMIT cost base net amount - excess (decrease cost base)', '0.00'),
  row('AMIT cost base net amount - shortfall (increase cost base)', '5.00'),
];
ManagedFundExtractionResult parse(List<FundPdfRow> rows) =>
    ManagedFundStatementParser().parse(
      rows,
      userId: 'synthetic',
      sourceHash: 'synthetic-hash',
    );

void main() {
  test(
    'Synthetic PDF bytes preserve spatial amounts through the actual PDF engine',
    () async {
      final document = PdfDocument();
      final page = document.pages.add();
      final font = PdfStandardFont(PdfFontFamily.helvetica, 8);
      final rows = fixture();
      for (var i = 0; i < rows.length; i++) {
        final y = 20.0 + i * 25;
        page.graphics.drawString(
          rows[i].label,
          font,
          bounds: Rect.fromLTWH(20, y, 470, 20),
        );
        for (final cell in rows[i].amounts) {
          page.graphics.drawString(
            cell.value,
            font,
            bounds: Rect.fromLTWH(520, y, 50, 20),
          );
        }
      }
      final bytes = await document.save();
      document.dispose();
      final result = await ManagedFundPdfService().extract(
        bytes,
        userId: 'synthetic',
      );
      expect(result.draft.issuer, 'Betashares');
      expect(result.draft.components['grossCapitalGain'], '220');
      expect(result.draft.components['discountedCapitalGain'], '100');
      expect(result.draft.components['amitShortfall'], '5');
      expect(result.draft.isReviewed, isFalse);
    },
  );
  test(
    'Betashares item-18 total is grossed already; detailed rows are not additional gains',
    () {
      final result = parse([
        ...fixture(),
        row('Capital gains - Discounted method TAP (Other)', '999.00'),
      ]);
      expect(result.draft.components['discountedCapitalGain'], '100');
      expect(result.draft.components['grossCapitalGain'], '220');
      expect(result.draft.components['otherCapitalGain'], '20');
      expect(result.draft.isReviewed, isFalse);
      expect(result.draft.adjustments, isEmpty);
      expect(result.draft.drpLinks, isEmpty);
      expect(result.draft.yearStart, 2024);
      expect(result.draft.ticker, 'SYN');
      expect(result.draft.accountNumber, 'SYNTHETIC-ACCOUNT');
      expect(result.draft.sourceReference, contains('pages:1'));
    },
  );
  test(
    'Missing fields stay blank, including Australian income and withholding',
    () {
      final result = parse(fixture());
      expect(result.draft.components['australianIncome'], '');
      expect(result.draft.components['withholding'], '');
      expect(
        result.missingFields,
        containsAll(['australianIncome', 'withholding']),
      );
    },
  );
  test(
    'iShares distinct discounted attribution components are summed once',
    () {
      final rows = fixture(issuer: 'iShares')
        ..removeWhere(
          (r) => r.label.startsWith('Capital gains - Discounted method'),
        );
      final result = parse([
        ...rows,
        row('Discounted capital gains TAP', '60.00'),
        row('Discounted capital gains NTAP', '40.00'),
        row('Capital gains - other method TAP', '20.00'),
        row('Capital gains - other method NTAP', '0.00'),
        row('Discounted capital gains NTAP', '40.00'),
      ]);
      expect(result.draft.components['discountedCapitalGain'], '100');
      expect(result.draft.components['otherCapitalGain'], '20');
      expect(
        result.warnings.any((w) => w.contains('do not reconcile')),
        isFalse,
      );
    },
  );
  test(
    'Cash/offset columns are not substituted for an empty attribution cell',
    () {
      final rows = fixture()
        ..removeWhere(
          (r) => r.label.startsWith('AMIT cost base net amount - shortfall'),
        );
      final result = parse([
        ...rows,
        row(
          'AMIT cost base net amount - shortfall (increase cost base)',
          '123.00',
          .60,
        ),
      ]);
      expect(result.draft.components['amitShortfall'], '');
    },
  );
  test('Ambiguous multiple amount columns require manual entry', () {
    final rows = fixture()
      ..removeWhere((r) => r.label.startsWith('Gross cash'));
    final result = parse([
      ...rows,
      const FundPdfRow(1, 'Gross cash distribution', [
        FundPdfAmount('50.00', .85),
        FundPdfAmount('80.00', .95),
      ]),
    ]);
    expect(result.draft.components['cashDistributions'], '');
  });
  test(
    'Conflicting repeated summaries are blank, not summed or overwritten',
    () {
      final result = parse([
        ...fixture(),
        row('Total current year capital gains', '300.00'),
      ]);
      expect(result.draft.components['grossCapitalGain'], '');
      expect(
        result.warnings.any((w) => w.contains('Conflicting repeated')),
        isTrue,
      );
    },
  );
  test('Multiple complete statements require page selection', () {
    final result = parse([...fixture(), ...fixture()]);
    expect(result.draft.issuer, '');
    expect(result.draft.components.values.every((v) => v.isEmpty), isTrue);
  });
  test('Reference instructions are not accepted as tax statement data', () {
    final result = parse([row('Reference pack'), ...fixture()]);
    expect(result.draft.components.values.every((v) => v.isEmpty), isTrue);
  });
  test('Unknown issuer and image-only text have a manual fallback', () {
    for (final rows in [fixture(issuer: 'Unknown issuer'), <FundPdfRow>[]]) {
      expect(parse(rows).draft.issuer, '');
      expect(parse(rows).missingFields, contains('issuer'));
    }
  });
  test('Mixed issuer content is not assigned to the first matching brand', () {
    final result = parse([...fixture(), row('iShares')]);
    expect(result.draft.issuer, '');
    expect(
      result.draft.components.values.every((value) => value.isEmpty),
      isTrue,
    );
  });
  test('Already grossed-up half-cent result is left for review', () {
    final rows = fixture()
      ..removeWhere(
        (r) => r.label.startsWith('Capital gains - Discounted method'),
      );
    expect(
      parse([
        ...rows,
        row('Capital gains - Discounted method (grossed up amount)', '200.01'),
      ]).draft.components['discountedCapitalGain'],
      '',
    );
  });
  test('Negative or malformed money does not become a confirmed field', () {
    for (final value in ['-5.00', 'NaN', '5.001']) {
      final rows = fixture()
        ..removeWhere((r) => r.label.startsWith('Gross cash'));
      expect(
        parse([
          ...rows,
          row('Gross cash distribution', value),
        ]).draft.components['cashDistributions'],
        '',
      );
    }
  });
  test(
    'Evidence does not echo source amounts, names or account identifiers',
    () {
      final result = parse(fixture());
      final output = [
        ...result.warnings,
        ...result.missingFields,
        ...result.fieldEvidence.values,
      ].join(' ');
      expect(output, isNot(contains('SYNTHETIC-ACCOUNT')));
      expect(output, isNot(contains('220.00')));
    },
  );
  test(
    'Corrupt bytes and invalid page selection produce a safe error',
    () async {
      await expectLater(
        ManagedFundPdfService().extract([1, 2, 3], userId: 'synthetic'),
        throwsFormatException,
      );
      final document = PdfDocument();
      document.pages.add();
      final bytes = await document.save();
      document.dispose();
      await expectLater(
        ManagedFundPdfService().extract(
          bytes,
          userId: 'synthetic',
          firstPage: 2,
          lastPage: 2,
        ),
        throwsFormatException,
      );
    },
  );
  test('Image-only PDF is a blank unreviewed draft', () async {
    final document = PdfDocument();
    document.pages.add();
    final bytes = await document.save();
    document.dispose();
    final result = await ManagedFundPdfService().extract(
      bytes,
      userId: 'synthetic',
    );
    expect(result.draft.isReviewed, isFalse);
    expect(result.draft.components.values.every((v) => v.isEmpty), isTrue);
    expect(result.sourceHash, hasLength(64));
  });
}
