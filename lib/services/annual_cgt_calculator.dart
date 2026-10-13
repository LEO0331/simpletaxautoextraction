import '../models/investment_ledger.dart';
import '../models/tax_decimal.dart';

class CapitalLossCarryForward {
  final int originStartYear;
  final String amount;
  final String evidenceReference;
  const CapitalLossCarryForward({
    required this.originStartYear,
    required this.amount,
    required this.evidenceReference,
  });
  Map<String, dynamic> toMap() => {
    'originStartYear': originStartYear,
    'amount': amount,
    'evidenceReference': evidenceReference,
  };
}

class AnnualCgtContext {
  final bool confirmedContinuousResident;
  final bool confirmedNonTemporaryResident;
  final bool completeHistory;
  final bool noPendingFundAdjustments;
  final bool priorLossesReviewed;
  final bool confirmedSupportedAssets;
  final String priorLosses;
  final List<CapitalLossCarryForward> priorLossBalances;
  const AnnualCgtContext({
    this.confirmedContinuousResident = false,
    this.confirmedNonTemporaryResident = false,
    this.completeHistory = false,
    this.noPendingFundAdjustments = false,
    this.priorLossesReviewed = false,
    this.confirmedSupportedAssets = false,
    this.priorLosses = '0',
    this.priorLossBalances = const [],
  });
  Map<String, dynamic> toMap() => {
    'confirmedContinuousResident': confirmedContinuousResident,
    'confirmedNonTemporaryResident': confirmedNonTemporaryResident,
    'completeHistory': completeHistory,
    'noPendingFundAdjustments': noPendingFundAdjustments,
    'priorLossesReviewed': priorLossesReviewed,
    'confirmedSupportedAssets': confirmedSupportedAssets,
    'priorLosses': priorLosses,
    'priorLossBalances': priorLossBalances.map((loss) => loss.toMap()).toList(),
  };
}

class AnnualCgtResult {
  final TaxYear year;
  final List<String> issues;
  final TaxDecimal totalCapitalGains;
  final TaxDecimal currentYearLosses;
  final TaxDecimal priorLossesUsed;
  final TaxDecimal lossesCarriedForward;
  final TaxDecimal? netCapitalGain;
  final List<Map<String, dynamic>> lossApplications;
  final Map<String, dynamic> snapshot;
  AnnualCgtResult({
    required this.year,
    required this.issues,
    required this.totalCapitalGains,
    required this.currentYearLosses,
    required this.priorLossesUsed,
    required this.lossesCarriedForward,
    required this.netCapitalGain,
    required this.lossApplications,
    required Map<String, dynamic> snapshot,
  }) : snapshot = freezeTaxSnapshot(snapshot);
  bool get needsReview => issues.isNotEmpty;
  String get status => needsReview ? 'NeedsTaxReview' : 'ReviewedWorksheet';
  Map<String, dynamic> toMap() => {
    'year': year.toString(),
    'status': status,
    'issues': issues,
    'totalCapitalGains': totalCapitalGains.toString(),
    'currentYearLosses': currentYearLosses.toString(),
    'priorLossesUsed': priorLossesUsed.toString(),
    'lossesCarriedForward': lossesCarriedForward.toString(),
    'netCapitalGain': netCapitalGain?.toString(),
    'lossApplications': lossApplications,
    'snapshot': snapshot,
  };
}

/// Reviewed resident individual worksheet for the explicitly supported rule years.
class AnnualCgtCalculator {
  AnnualCgtResult calculate({
    required InvestmentLedgerResult ledger,
    required TaxYear year,
    required AnnualCgtContext context,
  }) {
    final issues = [...ledger.issues];
    if (year.startYear != 2024 && year.startYear != 2025) {
      issues.add('Unsupported financial-year rule set');
    }
    if (!context.confirmedContinuousResident ||
        !context.confirmedNonTemporaryResident) {
      issues.add('Residency requires tax review');
    }
    if (!context.completeHistory) {
      issues.add('Acquisition and disposal history is incomplete');
    }
    if (!context.noPendingFundAdjustments) {
      issues.add('Fund adjustments or attributed gains require reconciliation');
    }
    if (!context.priorLossesReviewed) {
      issues.add('Prior capital losses, including zero, require review');
    }
    if (!context.confirmedSupportedAssets) {
      issues.add(
        'Confirm ordinary AUD investments with no special asset treatment',
      );
    }
    var prior = TaxDecimal.zero;
    try {
      prior = TaxDecimal.parse(context.priorLosses);
      if (prior.isNegative || prior != prior.rounded()) throw FormatException();
    } on FormatException {
      issues.add('Invalid prior losses');
      prior = TaxDecimal.zero;
    }
    final balances = [...context.priorLossBalances]
      ..sort((a, b) => a.originStartYear.compareTo(b.originStartYear));
    final opening = <TaxDecimal>[];
    final remaining = <TaxDecimal>[];
    try {
      final originYears = <int>{};
      for (final balance in balances) {
        final amount = TaxDecimal.parse(balance.amount);
        if (balance.originStartYear < 1900 ||
            balance.originStartYear >= year.startYear ||
            !originYears.add(balance.originStartYear) ||
            balance.evidenceReference.trim().isEmpty ||
            amount.isNegative ||
            amount != amount.rounded()) {
          throw const FormatException();
        }
        opening.add(amount);
        remaining.add(amount);
      }
      if (opening.fold(TaxDecimal.zero, (sum, amount) => sum + amount) !=
          prior) {
        throw const FormatException();
      }
    } on FormatException {
      issues.add(
        'Prior losses require matching originating years and evidence',
      );
      opening.clear();
      remaining.clear();
    }
    final events =
        [
          ...ledger.disposals.map(_AnnualCgtEvent.disposal),
          ...ledger.fundGains.map(_AnnualCgtEvent.fund),
        ].where((d) => year.contains(d.disposalDate)).toList()..sort((a, b) {
          final eligibility = (a.discountEligible ? 1 : 0).compareTo(
            b.discountEligible ? 1 : 0,
          );
          if (eligibility != 0) return eligibility;
          final date = a.disposalDate.compareTo(b.disposalDate);
          return date != 0
              ? date
              : '${a.sellTransactionId}/${a.buyTransactionId}'.compareTo(
                  '${b.sellTransactionId}/${b.buyTransactionId}',
                );
        });
    if (events.any(
      (d) => (d.acquisitionDate?.isBefore(DateTime(1999, 9, 21)) ?? false),
    )) {
      issues.add('Pre-CGT or indexed-era acquisitions require tax review');
    }
    if (events.any(
      (d) =>
          d.acquisitionDate?.month == 2 &&
          d.acquisitionDate?.day == 29 &&
          d.disposalDate.year == d.acquisitionDate!.year + 1 &&
          !d.disposalDate.isAfter(DateTime(d.disposalDate.year, 3, 1)),
    )) {
      issues.add('Leap-day anniversary boundary requires tax review');
    }
    var total = TaxDecimal.zero;
    var current = TaxDecimal.zero;
    for (final d in events) {
      total += d.capitalGain;
      current += d.capitalLoss;
    }
    var currentRemaining = current;
    var priorRemaining = prior;
    var net = TaxDecimal.zero;
    final applications = <Map<String, dynamic>>[];
    for (final d in events) {
      var gain = d.capitalGain;
      if (gain.isZero) continue;
      final currentUsed = gain < currentRemaining ? gain : currentRemaining;
      gain -= currentUsed;
      currentRemaining -= currentUsed;
      final priorUsed = gain < priorRemaining ? gain : priorRemaining;
      gain -= priorUsed;
      priorRemaining -= priorUsed;
      var toUse = priorUsed;
      final originsUsed = <Map<String, dynamic>>[];
      for (var i = 0; i < remaining.length && !toUse.isZero; i++) {
        final used = toUse < remaining[i] ? toUse : remaining[i];
        remaining[i] -= used;
        toUse -= used;
        if (!used.isZero) {
          originsUsed.add({
            'originStartYear': balances[i].originStartYear,
            'amount': used.toString(),
            'evidenceReference': balances[i].evidenceReference,
          });
        }
      }
      // Retain half-cent precision; currency rounding belongs to final summary.
      final discounted = d.discountEligible
          ? gain * TaxDecimal.parse('0.5')
          : gain;
      net += discounted;
      applications.add({
        'sellTransactionId': d.sellTransactionId,
        'buyTransactionId': d.buyTransactionId,
        'sourceKind': d.sourceKind,
        if (d.statementId != null) 'statementId': d.statementId,
        'currentLossUsed': currentUsed.toString(),
        'priorLossUsed': priorUsed.toString(),
        'priorLossOriginsUsed': originsUsed,
        'gainAfterLosses': gain.toString(),
        'discountApplied': d.discountEligible,
        'netGain': discounted.toString(),
      });
    }
    return AnnualCgtResult(
      year: year,
      issues: List.unmodifiable(issues),
      totalCapitalGains: total,
      currentYearLosses: current,
      priorLossesUsed: prior - priorRemaining,
      lossesCarriedForward: currentRemaining + priorRemaining,
      netCapitalGain: issues.isEmpty ? net : null,
      lossApplications: applications,
      snapshot: {
        'calculationVersion': 'annual-cgt-v2',
        'ruleVersion': 'AU-individual-resident-${year.toString()}-v1',
        'context': context.toMap(),
        'ledger': ledger.toMap(),
        'roundingPolicy':
            'Currency allocation half away from zero to cents; final parcel consumes residual; discount precision retained',
        'lossAllocationPolicy':
            'Current year, then oldest prior year; non-discount gains before discount gains',
        'closingLossBalances': [
          for (var i = 0; i < remaining.length; i++)
            {
              'originStartYear': balances[i].originStartYear,
              'openingAmount': opening[i].toString(),
              'usedAmount': (opening[i] - remaining[i]).toString(),
              'remainingAmount': remaining[i].toString(),
              'evidenceReference': balances[i].evidenceReference,
            },
          if (!currentRemaining.isZero)
            {
              'originStartYear': year.startYear,
              'openingAmount': current.toString(),
              'usedAmount': (current - currentRemaining).toString(),
              'remainingAmount': currentRemaining.toString(),
              'evidenceReference': 'Reviewed disposal ledger',
            },
        ],
      },
    );
  }
}

/// Annual gain sources retain their actual dates: fund attribution is not a sale.
class _AnnualCgtEvent {
  final String sellTransactionId, buyTransactionId, sourceKind;
  final String? statementId;
  final DateTime? acquisitionDate;
  final DateTime disposalDate;
  final TaxDecimal capitalGain, capitalLoss;
  final bool discountEligible;
  _AnnualCgtEvent.disposal(RealisedDisposal d)
    : sellTransactionId = d.sellTransactionId,
      buyTransactionId = d.buyTransactionId,
      sourceKind = 'disposal',
      statementId = null,
      acquisitionDate = d.acquisitionDate,
      disposalDate = d.disposalDate,
      capitalGain = d.capitalGain,
      capitalLoss = d.capitalLoss,
      discountEligible = d.discountEligible;
  _AnnualCgtEvent.fund(FundCapitalGainEvent g)
    : sellTransactionId = 'fund:${g.statementId}:${g.kind}',
      buyTransactionId = g.reference,
      sourceKind = g.kind,
      statementId = g.statementId,
      acquisitionDate = g.acquisitionDate,
      disposalDate = g.date,
      capitalGain = g.gain,
      capitalLoss = TaxDecimal.zero,
      discountEligible = g.discountEligible;
}
