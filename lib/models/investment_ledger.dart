import 'tax_decimal.dart';

class TaxYear {
  final int startYear;
  TaxYear(this.startYear) {
    if (startYear < 1900 || startYear > 2199) {
      throw ArgumentError.value(
        startYear,
        'startYear',
        'Expected 1900 to 2199',
      );
    }
  }
  DateTime get start => DateTime.utc(startYear, 7);
  DateTime get endExclusive => DateTime.utc(startYear + 1, 7);
  bool contains(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    return !day.isBefore(start) && day.isBefore(endExclusive);
  }

  @override
  String toString() => '$startYear-${startYear + 1}';
}

class ParcelSelection {
  final String buyTransactionId;
  final String units;
  const ParcelSelection({required this.buyTransactionId, required this.units});
  Map<String, dynamic> toMap() => {
    'buyTransactionId': buyTransactionId,
    'units': units,
  };
  factory ParcelSelection.fromMap(Map<String, dynamic> map) => ParcelSelection(
    buyTransactionId: map['buyTransactionId'] as String,
    units: map['units'] as String,
  );
}

class SaleAllocation {
  final String sellTransactionId;
  final List<ParcelSelection> selections;
  final String method;
  final int revision;
  final Map<String, int> transactionRevisions;
  const SaleAllocation({
    required this.sellTransactionId,
    required this.selections,
    this.method = 'specific',
    this.revision = 0,
    this.transactionRevisions = const {},
  });
  Map<String, dynamic> toMap() => {
    'sellTransactionId': sellTransactionId,
    'selections': selections.map((s) => s.toMap()).toList(),
    'method': method,
    'revision': revision,
    'transactionRevisions': Map<String, int>.from(transactionRevisions),
  };
  factory SaleAllocation.fromMap(Map<String, dynamic> map) => SaleAllocation(
    sellTransactionId: map['sellTransactionId'] as String,
    selections: (map['selections'] as List)
        .map(
          (s) => ParcelSelection.fromMap(Map<String, dynamic>.from(s as Map)),
        )
        .toList(),
    method: map['method'] as String? ?? 'specific',
    revision: map['revision'] as int? ?? 0,
    transactionRevisions: Map<String, int>.from(
      map['transactionRevisions'] as Map? ?? {},
    ),
  );
}

class InvestmentParcel {
  final String buyTransactionId;
  final String ticker;
  final String accountNumber;
  final DateTime acquisitionDate;
  final TaxDecimal originalUnits;
  final TaxDecimal remainingUnits;
  final TaxDecimal originalCostBase;
  final TaxDecimal remainingCostBase;

  /// Separate loss basis, reserved for future adjustments that affect one basis only.
  final TaxDecimal remainingReducedCostBase;
  const InvestmentParcel({
    required this.buyTransactionId,
    required this.ticker,
    required this.accountNumber,
    required this.acquisitionDate,
    required this.originalUnits,
    required this.remainingUnits,
    required this.originalCostBase,
    required this.remainingCostBase,
    required this.remainingReducedCostBase,
  });
  Map<String, dynamic> toMap() => {
    'buyTransactionId': buyTransactionId,
    'ticker': ticker,
    'accountNumber': accountNumber,
    'acquisitionDate': acquisitionDate.toIso8601String(),
    'originalUnits': originalUnits.toString(),
    'remainingUnits': remainingUnits.toString(),
    'originalCostBase': originalCostBase.toString(),
    'remainingCostBase': remainingCostBase.toString(),
    'remainingReducedCostBase': remainingReducedCostBase.toString(),
  };
}

class RealisedDisposal {
  final String sellTransactionId;
  final String buyTransactionId;
  final DateTime acquisitionDate;
  final DateTime disposalDate;
  final TaxDecimal units;
  final TaxDecimal grossProceeds;
  final TaxDecimal disposalCosts;
  final TaxDecimal costBase;
  final TaxDecimal reducedCostBase;
  const RealisedDisposal({
    required this.sellTransactionId,
    required this.buyTransactionId,
    required this.acquisitionDate,
    required this.disposalDate,
    required this.units,
    required this.grossProceeds,
    required this.disposalCosts,
    required this.costBase,
    required this.reducedCostBase,
  });
  TaxDecimal get netProceeds => grossProceeds - disposalCosts;
  TaxDecimal get taxCostBase => costBase + disposalCosts;
  TaxDecimal get taxReducedCostBase => reducedCostBase + disposalCosts;
  TaxDecimal get capitalGain =>
      netProceeds > costBase ? netProceeds - costBase : TaxDecimal.zero;
  TaxDecimal get capitalLoss => netProceeds < reducedCostBase
      ? reducedCostBase - netProceeds
      : TaxDecimal.zero;
  bool get discountEligible {
    // Exclude acquisition and disposal days: disposal must follow anniversary.
    final year = acquisitionDate.year + 1;
    final month = acquisitionDate.month;
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    final day = acquisitionDate.day > lastDay ? lastDay : acquisitionDate.day;
    return DateTime.utc(
      disposalDate.year,
      disposalDate.month,
      disposalDate.day,
    ).isAfter(DateTime.utc(year, month, day));
  }

  Map<String, dynamic> toMap() => {
    'sellTransactionId': sellTransactionId,
    'buyTransactionId': buyTransactionId,
    'acquisitionDate': acquisitionDate.toIso8601String(),
    'disposalDate': disposalDate.toIso8601String(),
    'units': units.toString(),
    'grossProceeds': grossProceeds.toString(),
    'disposalCosts': disposalCosts.toString(),
    'costBase': costBase.toString(),
    'reducedCostBase': reducedCostBase.toString(),
    'taxCostBase': taxCostBase.toString(),
    'taxReducedCostBase': taxReducedCostBase.toString(),
    'capitalGain': capitalGain.toString(),
    'capitalLoss': capitalLoss.toString(),
    'discountEligible': discountEligible,
  };
}

class InvestmentLedgerResult {
  final List<InvestmentParcel> parcels;
  final List<RealisedDisposal> disposals;
  final List<String> issues;
  final List<Map<String, dynamic>> inputSnapshot;
  InvestmentLedgerResult({
    required List<InvestmentParcel> parcels,
    required List<RealisedDisposal> disposals,
    required List<String> issues,
    required List<Map<String, dynamic>> inputSnapshot,
  }) : parcels = List.unmodifiable(parcels),
       disposals = List.unmodifiable(disposals),
       issues = List.unmodifiable(issues),
       inputSnapshot = List.unmodifiable(inputSnapshot.map(freezeTaxSnapshot));
  bool get needsReview => issues.isNotEmpty;
  Map<String, dynamic> toMap() => {
    'calculationVersion': 'parcel-v1',
    'parcels': parcels.map((p) => p.toMap()).toList(),
    'disposals': disposals.map((d) => d.toMap()).toList(),
    'issues': issues,
    'inputSnapshot': inputSnapshot,
    'inputRevisions': {for (final t in inputSnapshot) t['id']: t['revision']},
    'allocationRevisions': {
      for (final t in inputSnapshot)
        if (t['allocation'] != null)
          t['id']: (t['allocation'] as Map)['revision'],
    },
  };
}

/// Copies JSON-compatible provenance recursively so edits cannot alter a result.
Map<String, dynamic> freezeTaxSnapshot(Map<String, dynamic> source) =>
    Map<String, dynamic>.unmodifiable(
      source.map((key, value) => MapEntry(key, _freezeTaxValue(value))),
    );

dynamic _freezeTaxValue(dynamic value) {
  if (value is Map) {
    return freezeTaxSnapshot(Map<String, dynamic>.from(value));
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(value.map(_freezeTaxValue));
  }
  return value;
}
