import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/investment_cgt_calculation.dart';
import '../models/tax_record.dart';
import '../models/investment_transaction.dart';

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

  String exportInvestmentTransactionsToCsv(
    List<InvestmentTransaction> transactions,
  ) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Ticker,Security Name,Type,Trade Date,Settlement Date,Units,Average Price,Consideration,Brokerage,GST,Total Cost,Confirmation No,Account No,Source File,Locked,Notes',
    );
    for (final t in transactions) {
      buffer.writeln(
        [
          _escape(t.ticker),
          _escape(t.securityName),
          _escape(t.transactionType.value),
          _escape(t.tradeDate.toIso8601String().split('T').first),
          _escape(
            t.settlementDate == null
                ? ''
                : t.settlementDate!.toIso8601String().split('T').first,
          ),
          t.units.toStringAsFixed(6),
          t.averagePrice.toStringAsFixed(6),
          t.consideration.toStringAsFixed(2),
          t.brokerage.toStringAsFixed(2),
          (t.gst ?? 0).toStringAsFixed(2),
          t.totalCost.toStringAsFixed(2),
          _escape(t.confirmationNumber ?? ''),
          _escape(t.accountNumber ?? ''),
          _escape(t.sourceFileName ?? ''),
          t.isLocked ? 'Yes' : 'No',
          _escape(t.notes),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  String exportInvestmentCgtCalculationToCsv(
    List<InvestmentCgtCalculation> calculations,
  ) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Ticker,Security Name,Type,Trade Date,Units,Cost Base,Cut-off Date,Cut-off Price,Market Value,Estimated Gain/Loss,Gain/Loss %,Holding Days,Potential Discount Eligible,Estimated Taxable Gain',
    );
    for (final c in calculations) {
      final t = c.transaction;
      buffer.writeln(
        [
          _escape(t.ticker),
          _escape(t.securityName),
          _escape(t.transactionType.value),
          _escape(t.tradeDate.toIso8601String().split('T').first),
          t.units.toStringAsFixed(6),
          t.totalCost.toStringAsFixed(2),
          _escape(c.cutOffDate.toIso8601String().split('T').first),
          c.cutOffPrice.toStringAsFixed(6),
          c.marketValueAtCutOff.toStringAsFixed(2),
          c.estimatedGainLoss.toStringAsFixed(2),
          c.gainLossPercent.toStringAsFixed(2),
          c.holdingDays.toString(),
          c.potentialCgtDiscountEligible ? 'Yes' : 'No',
          c.estimatedTaxableGainAfterDiscount.toStringAsFixed(2),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  String exportInvestmentTransactionsToJson(
    List<InvestmentTransaction> transactions,
  ) {
    final list = transactions
        .map(
          (t) => {
            ...t.toMap(),
            'id': t.id,
            'tradeDate': t.tradeDate.toIso8601String(),
            'settlementDate': t.settlementDate?.toIso8601String(),
            'createdAt': t.createdAt?.toIso8601String(),
            'updatedAt': t.updatedAt?.toIso8601String(),
          },
        )
        .toList();
    return const JsonEncoder.withIndent('  ').convert(list);
  }
}
