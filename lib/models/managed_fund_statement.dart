import 'tax_decimal.dart';

class FundCostBaseAdjustment {
  final String parcelId, amount, date, evidenceReference;
  final String? beforeSaleId, units, reducedAmount;
  const FundCostBaseAdjustment({
    required this.parcelId,
    required this.amount,
    required this.date,
    required this.evidenceReference,
    this.beforeSaleId,
    this.units,
    this.reducedAmount,
  });
  Map<String, dynamic> toMap() => {
    'parcelId': parcelId,
    'amount': amount,
    'date': date,
    'evidenceReference': evidenceReference,
    'beforeSaleId': beforeSaleId,
    'units': units,
    if (reducedAmount != null) 'reducedAmount': reducedAmount,
  };
  factory FundCostBaseAdjustment.fromMap(Map<String, dynamic> m) =>
      FundCostBaseAdjustment(
        parcelId: m['parcelId'] as String,
        amount: m['amount'] as String,
        date: m['date'] as String,
        evidenceReference: m['evidenceReference'] as String,
        beforeSaleId: m['beforeSaleId'] as String?,
        units: m['units'] as String?,
        reducedAmount: m['reducedAmount'] as String?,
      );
}

class FundDrpLink {
  final String buyTransactionId,
      cashEntitlement,
      reinvestedAmount,
      residualCash,
      evidenceReference;
  const FundDrpLink({
    required this.buyTransactionId,
    required this.cashEntitlement,
    required this.reinvestedAmount,
    required this.residualCash,
    required this.evidenceReference,
  });
  Map<String, dynamic> toMap() => {
    'buyTransactionId': buyTransactionId,
    'cashEntitlement': cashEntitlement,
    'reinvestedAmount': reinvestedAmount,
    'residualCash': residualCash,
    'evidenceReference': evidenceReference,
  };
  factory FundDrpLink.fromMap(Map<String, dynamic> m) => FundDrpLink(
    buyTransactionId: m['buyTransactionId'] as String,
    cashEntitlement: m['cashEntitlement'] as String,
    reinvestedAmount: m['reinvestedAmount'] as String,
    residualCash: m['residualCash'] as String,
    evidenceReference: m['evidenceReference'] as String,
  );
}

/// Manually reviewed issuer/year statement. No PDF text or tax identifiers stored.
class ManagedFundStatement {
  static const componentKeys = [
    'australianIncome',
    'foreignIncome',
    'frankingCredits',
    'foreignTaxOffset',
    'withholding',
    'cashDistributions',
    'discountedCapitalGain',
    'otherCapitalGain',
    'grossCapitalGain',
    'amitShortfall',
    'amitExcess',
  ];
  static const nonAmitComponentKeys = ['taxDeferred', 'taxFree', 'taxExempt'];
  static const allComponentKeys = [...componentKeys, ...nonAmitComponentKeys];
  final String? id;
  final String userId,
      ticker,
      accountNumber,
      issuer,
      layoutVersion,
      sourceReference,
      regime;
  final int yearStart, revision;
  final bool isReviewed, isVoided;
  final Map<String, String> components;
  final List<FundCostBaseAdjustment> adjustments;
  final List<FundDrpLink> drpLinks;
  const ManagedFundStatement({
    required this.id,
    required this.userId,
    required this.ticker,
    required this.accountNumber,
    required this.issuer,
    required this.layoutVersion,
    required this.yearStart,
    required this.sourceReference,
    this.regime = 'AMIT',
    this.revision = 0,
    this.isReviewed = false,
    this.isVoided = false,
    this.components = const {},
    this.adjustments = const [],
    this.drpLinks = const [],
  });
  String get identity => '$userId|$ticker|$accountNumber|$yearStart';
  TaxDecimal component(String key) => TaxDecimal.parse(components[key] ?? '0');
  Map<String, dynamic> toMap() => {
    'schemaVersion': 1,
    'userId': userId,
    'ticker': ticker,
    'accountNumber': accountNumber,
    'issuer': issuer,
    'layoutVersion': layoutVersion,
    'yearStart': yearStart,
    'sourceReference': sourceReference,
    'regime': regime,
    'revision': revision,
    'isReviewed': isReviewed,
    'isVoided': isVoided,
    'components': Map<String, String>.from(components),
    'adjustments': adjustments.map((a) => a.toMap()).toList(),
    'drpLinks': drpLinks.map((a) => a.toMap()).toList(),
  };
  factory ManagedFundStatement.fromMap(Map<String, dynamic> m, {String? id}) =>
      ManagedFundStatement(
        id: id ?? m['id'] as String?,
        userId: m['userId'] as String,
        ticker: m['ticker'] as String,
        accountNumber: m['accountNumber'] as String,
        issuer: m['issuer'] as String,
        layoutVersion: m['layoutVersion'] as String,
        yearStart: m['yearStart'] as int,
        sourceReference: m['sourceReference'] as String,
        regime: m['regime'] as String? ?? 'AMIT',
        revision: m['revision'] as int? ?? 0,
        isReviewed: m['isReviewed'] == true,
        isVoided: m['isVoided'] == true,
        components: Map<String, String>.from(m['components'] as Map? ?? {}),
        adjustments: (m['adjustments'] as List? ?? [])
            .map(
              (v) => FundCostBaseAdjustment.fromMap(
                Map<String, dynamic>.from(v as Map),
              ),
            )
            .toList(),
        drpLinks: (m['drpLinks'] as List? ?? [])
            .map(
              (v) => FundDrpLink.fromMap(Map<String, dynamic>.from(v as Map)),
            )
            .toList(),
      );
  List<String> validation() {
    final issues = <String>[];
    if ([
          userId,
          ticker,
          accountNumber,
          issuer,
          layoutVersion,
          sourceReference,
        ].any((s) => s.trim().isEmpty) ||
        yearStart < 1900 ||
        yearStart > 2199) {
      issues.add(
        'Statement identity, issuer, layout, year and source are required',
      );
    }
    if (!['AMIT', 'NON_AMIT'].contains(regime)) {
      issues.add('Unknown fund regime requires tax review');
    }
    try {
      if (isReviewed && componentKeys.any((k) => !components.containsKey(k))) {
        issues.add(
          'Review requires every statement component, including explicit zeros',
        );
      }
      if (isReviewed &&
          regime == 'NON_AMIT' &&
          nonAmitComponentKeys.any((k) => !components.containsKey(k))) {
        issues.add(
          'Non-AMIT review requires explicit tax-deferred, tax-free and tax-exempt amounts',
        );
      }
      if (components.keys.any((k) => !allComponentKeys.contains(k))) {
        throw const FormatException('Unknown statement component');
      }
      for (final k in allComponentKeys) {
        final v = component(k);
        if (v.isNegative || v != v.rounded()) {
          throw const FormatException(
            'Statement amounts must be nonnegative cents',
          );
        }
      }
      if (component('grossCapitalGain') !=
          component('discountedCapitalGain') * TaxDecimal.parse('2') +
              component('otherCapitalGain')) {
        issues.add(
          'Gross capital gain must reconcile with twice discounted gain plus other gain',
        );
      }
      if (!component('amitShortfall').isZero &&
          !component('amitExcess').isZero) {
        issues.add('Shortfall and excess cannot both be reported');
      }
      if (regime != 'AMIT' &&
          (!component('amitShortfall').isZero ||
              !component('amitExcess').isZero)) {
        issues.add('Non-AMIT cost-base adjustments require tax review');
      }
      var sum = TaxDecimal.zero, reducedSum = TaxDecimal.zero;
      final expected = regime == 'NON_AMIT'
          ? TaxDecimal.zero - component('taxDeferred')
          : component('amitShortfall') - component('amitExcess');
      final expectedReduced = regime == 'NON_AMIT'
          ? expected - component('taxFree')
          : expected;
      if (adjustments.isNotEmpty && expected.isZero && expectedReduced.isZero) {
        issues.add(
          'A zero AMIT net amount cannot contain offsetting adjustment slices',
        );
      }
      final scopes = <String>{};
      for (final a in adjustments) {
        final amount = TaxDecimal.parse(a.amount);
        final reduced = TaxDecimal.parse(a.reducedAmount ?? a.amount);
        final date = parseFundDate(a.date);
        if ((amount.isZero && reduced.isZero) ||
            amount != amount.rounded() ||
            reduced != reduced.rounded() ||
            (regime == 'AMIT' && reduced != amount) ||
            (regime == 'NON_AMIT' &&
                (a.reducedAmount == null ||
                    amount > TaxDecimal.zero ||
                    reduced > amount)) ||
            a.parcelId.isEmpty ||
            a.evidenceReference.trim().isEmpty ||
            !scopes.add('${a.parcelId}|${a.beforeSaleId ?? a.date}')) {
          throw const FormatException('Invalid or repeated adjustment scope');
        }
        if (date.isBefore(DateTime.utc(yearStart, 7)) ||
            !date.isBefore(DateTime.utc(yearStart + 1, 7))) {
          throw const FormatException('Adjustment date outside statement year');
        }
        if (a.beforeSaleId == null && a.date != '${yearStart + 1}-06-30') {
          throw const FormatException(
            'Retained interest adjustment must occur at financial year end',
          );
        }
        if (a.units == null || TaxDecimal.parse(a.units!) <= TaxDecimal.zero) {
          throw const FormatException(
            'Adjustment requires evidenced interest units',
          );
        }
        if ((!component('amitShortfall').isZero && amount.isNegative) ||
            (!component('amitExcess').isZero && !amount.isNegative)) {
          issues.add(
            'Adjustment sign does not match statement shortfall/excess',
          );
        }
        sum += amount;
        reducedSum += reduced;
      }
      if (sum != expected || reducedSum != expectedReduced) {
        issues.add(
          'Parcel adjustments do not reconcile with statement cost and reduced-cost amounts',
        );
      }
      final buys = <String>{};
      var cash = TaxDecimal.zero;
      for (final d in drpLinks) {
        final entitlement = TaxDecimal.parse(d.cashEntitlement),
            reinvested = TaxDecimal.parse(d.reinvestedAmount),
            residual = TaxDecimal.parse(d.residualCash);
        if (!buys.add(d.buyTransactionId) ||
            d.buyTransactionId.isEmpty ||
            d.evidenceReference.trim().isEmpty ||
            entitlement.isNegative ||
            reinvested <= TaxDecimal.zero ||
            residual.isNegative ||
            entitlement != entitlement.rounded() ||
            reinvested != reinvested.rounded() ||
            residual != residual.rounded() ||
            entitlement != reinvested + residual) {
          throw const FormatException(
            'DRP cash entitlement must reconcile with reinvestment and residual',
          );
        }
        cash += entitlement;
      }
      if (cash > component('cashDistributions')) {
        issues.add('DRP entitlements exceed statement cash distributions');
      }
    } on FormatException catch (e) {
      issues.add(e.message);
    }
    return issues;
  }
}

DateTime parseFundDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid adjustment date');
  }
  final date = DateTime.tryParse('${value}T00:00:00Z');
  if (date == null || date.toIso8601String().substring(0, 10) != value) {
    throw const FormatException('Invalid adjustment date');
  }
  return date;
}
