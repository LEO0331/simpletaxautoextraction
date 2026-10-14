import '../../models/document_coverage.dart';
import '../../models/tax_decimal.dart';

class DrpAdviceDraft {
  final String? paymentDate, recordDate, units, reinvestedAmount, residualCash;
  final List<String> issues;
  const DrpAdviceDraft({
    this.paymentDate,
    this.recordDate,
    this.units,
    this.reinvestedAmount,
    this.residualCash,
    required this.issues,
  });
}

class DrpAdviceParser {
  DrpAdviceDraft parse(String text) {
    final supported =
        text.toLowerCase().contains('betashares') &&
        (text.toLowerCase().contains('distribution advice') ||
            text.toLowerCase().contains('distribution reinvestment'));
    if (!supported) {
      return const DrpAdviceDraft(
        issues: [
          'Unsupported advice layout. Enter and verify fields manually.',
        ],
      );
    }
    final lines = text.split(RegExp(r'[\r\n]+')).map((s) => s.trim()).toList();
    String? field(List<String> labels, {bool units = false}) {
      final matches = <String>[];
      for (final line in lines) {
        for (final label in labels) {
          final m = RegExp(
            '^${RegExp.escape(label)}\\s*:?\\s+([\\d,]+(?:\\.\\d+)?)\\s*\$',
            caseSensitive: false,
          ).firstMatch(line.replaceAll(r'$', ''));
          if (m != null) {
            try {
              final d = TaxDecimal.parse(m[1]!.replaceAll(',', ''));
              if (!d.isNegative && (units || d == d.rounded(2))) {
                matches.add(d.toString());
              }
            } catch (_) {}
          }
        }
      }
      return matches.length == 1 ? matches.single : null;
    }

    String? date(String label) {
      final matches = <String>[];
      for (final l in lines) {
        final m = RegExp(
          '^$label\\s*:?\\s+(\\d{4}-\\d{2}-\\d{2})\$',
          caseSensitive: false,
        ).firstMatch(l);
        if (m != null && parseDocumentDate(m[1]!) != null) matches.add(m[1]!);
        final written = RegExp(
          '^$label\\s*:?\\s+(\\d{1,2}) (January|February|March|April|May|June|July|August|September|October|November|December) (\\d{4})\$',
          caseSensitive: false,
        ).firstMatch(l);
        if (written != null) {
          const months = [
            'january',
            'february',
            'march',
            'april',
            'may',
            'june',
            'july',
            'august',
            'september',
            'october',
            'november',
            'december',
          ];
          final month = months.indexOf(written[2]!.toLowerCase()) + 1;
          final iso =
              '${written[3]}-${month.toString().padLeft(2, '0')}-${written[1]!.padLeft(2, '0')}';
          if (parseDocumentDate(iso) != null) matches.add(iso);
        }
      }
      return matches.length == 1 ? matches.single : null;
    }

    final payment = date('Payment date'),
        record = date('Record date'),
        units = field([
          'Units allotted',
          'Number of units allotted',
        ], units: true),
        amount = field([
          'Amount reinvested',
          'Distribution reinvested',
          'Amount applied to reinvestment',
        ]),
        residual = field([
          'Residual balance carried forward in your Plan account',
          'Residual cash',
        ]);
    return DrpAdviceDraft(
      paymentDate: payment,
      recordDate: record,
      units: units,
      reinvestedAmount: amount,
      residualCash: residual,
      issues: [
        if (payment == null) 'Payment date requires review.',
        if (record == null) 'Record date requires review.',
        if (units == null) 'Units allotted requires review.',
        if (amount == null) 'Reinvestment amount requires review.',
        if (residual == null) 'Residual cash requires review.',
      ],
    );
  }
}
