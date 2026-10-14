import '../models/tax_decimal.dart';
import '../models/managed_fund_statement.dart';

/// A conversion fact, not a forex gain calculation or exchange-rate lookup.
/// Acquisition costs and sale proceeds use separate dated evidence; reusing a
/// sale-date rate for historical acquisition costs is deliberately not implied.
class ForeignCurrencyConversion {
  final String currency, foreignAmount, audPerUnit, date, evidenceReference;
  final bool reviewed, separateForexReviewed;
  const ForeignCurrencyConversion({
    required this.currency,
    required this.foreignAmount,
    required this.audPerUnit,
    required this.date,
    required this.evidenceReference,
    this.reviewed = false,
    this.separateForexReviewed = false,
  });
  List<String> validation() {
    final issues = <String>[];
    try {
      parseFundDate(date);
      if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
          currency == 'AUD' ||
          TaxDecimal.parse(foreignAmount).isNegative ||
          TaxDecimal.parse(audPerUnit) <= TaxDecimal.zero ||
          evidenceReference.trim().isEmpty) {
        issues.add(
          'Conversion requires currency, nonnegative amount, positive AUD-per-unit rate and dated evidence',
        );
      }
    } on FormatException {
      issues.add('Invalid dated conversion amount or rate');
    }
    if (!reviewed) issues.add('Currency conversion requires review');
    if (!separateForexReviewed) {
      issues.add('Separate forex realisations and elections require review');
    }
    return issues;
  }

  TaxDecimal? get audAmount => validation().isEmpty
      ? (TaxDecimal.parse(foreignAmount) * TaxDecimal.parse(audPerUnit))
            .rounded()
      : null;
  Map<String, dynamic> toMap() => {
    'currency': currency,
    'foreignAmount': foreignAmount,
    'audPerUnit': audPerUnit,
    'date': date,
    'evidenceReference': evidenceReference,
    'reviewed': reviewed,
    'separateForexReviewed': separateForexReviewed,
    'audAmount': audAmount?.toString(),
  };
}
