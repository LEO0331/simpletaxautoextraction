import '../models/document_coverage.dart';
import '../models/investment_ledger.dart';
import '../models/tax_decimal.dart';

/// The supplied ledger must be replayed through the observation date.
List<String> reconcileHoldings(
  DocumentCoverage observation,
  InvestmentLedgerResult ledger,
) {
  if (!observation.family.endsWith('Holdings') ||
      observation.state != 'reviewed' ||
      observation.isVoided) {
    return const [];
  }
  final errors = observation.validation();
  if (errors.isNotEmpty) return errors;
  if (ledger.issues.isNotEmpty) {
    return [
      'Holdings cannot reconcile while the ledger needs review.',
      ...ledger.issues,
    ];
  }
  var units = TaxDecimal.zero;
  for (final p in ledger.parcels.where(
    (p) =>
        p.accountNumber == observation.account &&
        p.ticker == observation.ticker,
  )) {
    units = units + p.remainingUnits;
  }
  return units == TaxDecimal.parse(observation.unitsExact)
      ? const []
      : [
          'Observed holdings do not match recorded parcels for ${observation.account}/${observation.ticker}. Review missing trades or corporate actions; do not invent acquisitions.',
        ];
}
