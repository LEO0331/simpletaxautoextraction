import '../models/corporate_action_decision.dart';
import '../models/investment_ledger_fact.dart';
import '../models/investment_ledger.dart';
import '../models/tax_decimal.dart';
import '../models/managed_fund_statement.dart';

/// Replays explicit allocations. An invalid sale is atomic and consumes no units.
class InvestmentParcelLedger {
  InvestmentLedgerResult replay({
    required List<InvestmentLedgerFact> transactions,
    required List<SaleAllocation> allocations,
    List<ManagedFundStatement> statements = const [],
    List<CorporateActionDecision> corporateActions = const [],
    DateTime? asOfDate,
    bool reviewedFacts = true,
  }) {
    final issues = <String>[];
    final parcels = <String, InvestmentParcel>{};
    final disposals = <RealisedDisposal>[];
    final snapshots = <Map<String, dynamic>>[];
    final statementSnapshots = <Map<String, dynamic>>[];
    final history = <Map<String, dynamic>>[];
    final fundGains = <FundCapitalGainEvent>[];
    final validStatements = <ManagedFundStatement>[];
    final statementIdentities = <String>{},
        statementIds = <String>{},
        drpIds = <String>{};
    final owners = transactions
        .where((t) => !t.isVoided)
        .map((t) => t.userId)
        .toSet();
    final statementOwners = statements
        .where(
          (s) =>
              !s.isVoided &&
              (asOfDate == null ||
                  !DateTime.utc(s.yearStart, 7).isAfter(
                    DateTime.utc(asOfDate.year, asOfDate.month, asOfDate.day),
                  )),
        )
        .map((s) => s.userId)
        .toSet();
    for (final statement in statements.where(
      (s) =>
          !s.isVoided &&
          (asOfDate == null ||
              !DateTime.utc(s.yearStart, 7).isAfter(
                DateTime.utc(asOfDate.year, asOfDate.month, asOfDate.day),
              )),
    )) {
      statementSnapshots.add({'id': statement.id, ...statement.toMap()});
      final errors = statement.validation();
      if (statementOwners.length > 1) {
        errors.add('Statements must belong to one user');
      }
      if (!statement.isReviewed) errors.add('Statement must be reviewed');
      if (statement.id == null ||
          statement.id!.isEmpty ||
          !statementIds.add(statement.id!)) {
        errors.add('Missing or duplicate statement identity');
      }
      if (!statementIdentities.add(statement.identity)) {
        errors.add(
          'Duplicate annual statement requires replacement, not addition',
        );
      }
      if (owners.isNotEmpty &&
          (owners.length != 1 || !owners.contains(statement.userId))) {
        errors.add('Statement owner does not match transactions');
      }
      for (final d in errors.isEmpty ? statement.drpLinks : <FundDrpLink>[]) {
        final matches = transactions
            .where((t) => !t.isVoided && t.id == d.buyTransactionId)
            .toList();
        if (!drpIds.add(d.buyTransactionId) || matches.length != 1) {
          errors.add('DRP acquisition missing or linked more than once');
          continue;
        }
        final buy = matches.single;
        try {
          if (!buy.isBuy ||
              !buy.isReviewed ||
              buy.userId != statement.userId ||
              buy.ticker != statement.ticker ||
              buy.accountNumber != statement.accountNumber ||
              !TaxYear(statement.yearStart).contains(buy.tradeDate) ||
              buy.totalCostExact == null ||
              TaxDecimal.parse(buy.totalCostExact!) !=
                  TaxDecimal.parse(d.reinvestedAmount)) {
            errors.add(
              'DRP must reconcile with the reviewed existing acquisition',
            );
          }
        } on FormatException {
          errors.add('Invalid DRP acquisition amount');
        }
      }
      if (errors.isNotEmpty) {
        issues.addAll(errors.map((e) => '${statement.id ?? 'statement'}: $e'));
        continue;
      }
      validStatements.add(statement);
      final date = DateTime.utc(statement.yearStart + 1, 6, 30);
      if (asOfDate == null ||
          !date.isAfter(
            DateTime.utc(asOfDate.year, asOfDate.month, asOfDate.day),
          )) {
        for (final key in ['discountedCapitalGain', 'otherCapitalGain']) {
          final gain =
              statement.component(key) *
              (key == 'discountedCapitalGain'
                  ? TaxDecimal.parse('2')
                  : TaxDecimal.one);
          if (!gain.isZero) {
            fundGains.add(
              FundCapitalGainEvent(
                statementId: statement.id!,
                reference: key,
                kind: 'attributed',
                date: date,
                gain: gain,
                discountEligible: key == 'discountedCapitalGain',
              ),
            );
          }
        }
      }
    }
    if (statementSnapshots.map((s) => s['userId']).toSet().length > 1) {
      issues.add('Statements must belong to one user');
    }
    final actionSnapshots = <Map<String, dynamic>>[];
    final pendingActions = <CorporateActionDecision>[];
    final seenActions = <String>{};
    for (final action in corporateActions.where((a) => !a.isVoided)) {
      final errors = action.validation();
      if (errors.isNotEmpty ||
          !seenActions.add(action.id) ||
          owners.any((owner) => owner != action.userId) ||
          statementOwners.any((owner) => owner != action.userId)) {
        issues.add(
          '${action.id}: Review split/consolidation identity, ownership and evidence',
        );
        continue;
      }
      final date = parseFundDate(action.date);
      if (asOfDate != null &&
          date.isAfter(
            DateTime.utc(asOfDate.year, asOfDate.month, asOfDate.day),
          )) {
        continue;
      }
      pendingActions.add(action);
      actionSnapshots.add({'id': action.id, ...action.toMap()});
    }
    pendingActions.sort((a, b) {
      final date = a.date.compareTo(b.date);
      return date != 0 ? date : a.id.compareTo(b.id);
    });
    final pendingYearEnd =
        <MapEntry<ManagedFundStatement, FundCostBaseAdjustment>>[
          for (final statement in validStatements)
            for (final a in statement.adjustments)
              if (a.beforeSaleId == null) MapEntry(statement, a),
        ]..sort((a, b) => a.value.date.compareTo(b.value.date));
    void recordAdjustment(
      ManagedFundStatement statement,
      FundCostBaseAdjustment adjustment,
      InvestmentParcel parcel,
      TaxDecimal basis,
      TaxDecimal reduced,
      TaxDecimal amount,
    ) {
      final reducedAmount = TaxDecimal.parse(
        adjustment.reducedAmount ?? adjustment.amount,
      );
      final adjusted = basis + amount;
      final excess = adjusted.isNegative
          ? TaxDecimal.zero - adjusted
          : TaxDecimal.zero;
      history.add({
        'statementId': statement.id,
        'statementRevision': statement.revision,
        ...adjustment.toMap(),
        'openingCostBase': basis.toString(),
        'closingCostBase': (adjusted.isNegative ? TaxDecimal.zero : adjusted)
            .toString(),
        'openingReducedCostBase': reduced.toString(),
        'closingReducedCostBase':
            ((reduced + reducedAmount).isNegative
                    ? TaxDecimal.zero
                    : reduced + reducedAmount)
                .toString(),
        if (statement.regime == 'NON_AMIT') 'e4Gain': excess.toString(),
        if (statement.regime == 'AMIT') 'e10Gain': excess.toString(),
      });
      if (!excess.isZero) {
        final date = parseFundDate(adjustment.date);
        final anniversary = DateTime.utc(
          parcel.acquisitionDate.year + 1,
          parcel.acquisitionDate.month,
          parcel.acquisitionDate.day,
        );
        fundGains.add(
          FundCapitalGainEvent(
            statementId: statement.id!,
            reference: adjustment.parcelId,
            kind: statement.regime == 'NON_AMIT' ? 'E4' : 'E10',
            date: date,
            gain: excess,
            discountEligible: date.isAfter(anniversary),
            acquisitionDate: parcel.acquisitionDate,
          ),
        );
      }
    }

    void applyYearEnd(DateTime? before) {
      while (pendingYearEnd.isNotEmpty || pendingActions.isNotEmpty) {
        if (pendingActions.isNotEmpty &&
            (pendingYearEnd.isEmpty ||
                pendingActions.first.date.compareTo(
                      pendingYearEnd.first.value.date,
                    ) <=
                    0)) {
          final action = pendingActions.first;
          final date = parseFundDate(action.date);
          if (before != null && !date.isBefore(before)) break;
          final parcel = parcels[action.parcelId];
          pendingActions.removeAt(0);
          final sameDayFact = transactions.any(
            (t) =>
                (t.id == action.parcelId ||
                    allocations.any(
                      (a) =>
                          a.sellTransactionId == t.id &&
                          a.selections.any(
                            (s) => s.buyTransactionId == action.parcelId,
                          ),
                    )) &&
                DateTime.utc(
                      t.tradeDate.year,
                      t.tradeDate.month,
                      t.tradeDate.day,
                    ) ==
                    date &&
                !t.isVoided,
          );
          if (parcel == null ||
              parcel.remainingUnits != TaxDecimal.parse(action.oldUnits) ||
              !date.isAfter(parcel.acquisitionDate) ||
              sameDayFact) {
            issues.add(
              '${action.id}: Split interest or same-day ordering requires review',
            );
            continue;
          }
          final newUnits = TaxDecimal.parse(action.newUnits);
          parcels[action.parcelId] = InvestmentParcel(
            buyTransactionId: parcel.buyTransactionId,
            ticker: parcel.ticker,
            accountNumber: parcel.accountNumber,
            acquisitionDate: parcel.acquisitionDate,
            originalUnits: parcel.originalUnits,
            remainingUnits: newUnits,
            originalCostBase: parcel.originalCostBase,
            remainingCostBase: parcel.remainingCostBase,
            remainingReducedCostBase: parcel.remainingReducedCostBase,
          );
          history.add({
            'corporateActionId': action.id,
            'revision': action.revision,
            'kind': 'split',
            'date': action.date,
            'parcelId': action.parcelId,
            'oldUnits': action.oldUnits,
            'newUnits': action.newUnits,
            'evidenceReference': action.evidenceReference,
            'openingCostBase': parcel.remainingCostBase.toString(),
            'closingCostBase': parcel.remainingCostBase.toString(),
            'openingReducedCostBase': parcel.remainingReducedCostBase
                .toString(),
            'closingReducedCostBase': parcel.remainingReducedCostBase
                .toString(),
          });
          continue;
        }
        final entry = pendingYearEnd.first,
            a = entry.value,
            statement = entry.key;
        final date = parseFundDate(a.date);
        if (before != null && !date.isBefore(before)) break;
        if (asOfDate != null &&
            date.isAfter(
              DateTime.utc(asOfDate.year, asOfDate.month, asOfDate.day),
            )) {
          break;
        }
        pendingYearEnd.removeAt(0);
        final parcel = parcels[a.parcelId];
        if (parcel == null ||
            parcel.ticker != statement.ticker ||
            parcel.accountNumber != statement.accountNumber ||
            parcel.remainingUnits <= TaxDecimal.zero ||
            parcel.remainingUnits != TaxDecimal.parse(a.units!)) {
          issues.add(
            '${statement.id}: Year-end adjustment interest does not match retained parcel',
          );
          continue;
        }
        final amount = TaxDecimal.parse(a.amount),
            basis = parcel.remainingCostBase + amount,
            reduced =
                parcel.remainingReducedCostBase +
                TaxDecimal.parse(a.reducedAmount ?? a.amount);
        recordAdjustment(
          statement,
          a,
          parcel,
          parcel.remainingCostBase,
          parcel.remainingReducedCostBase,
          amount,
        );
        parcels[a.parcelId] = InvestmentParcel(
          buyTransactionId: parcel.buyTransactionId,
          ticker: parcel.ticker,
          accountNumber: parcel.accountNumber,
          acquisitionDate: parcel.acquisitionDate,
          originalUnits: parcel.originalUnits,
          remainingUnits: parcel.remainingUnits,
          originalCostBase: parcel.originalCostBase,
          remainingCostBase: basis.isNegative ? TaxDecimal.zero : basis,
          remainingReducedCostBase: reduced.isNegative
              ? TaxDecimal.zero
              : reduced,
        );
      }
    }

    final ordered =
        transactions
            .where((t) => !t.isVoided)
            .where(
              (t) =>
                  asOfDate == null ||
                  !DateTime.utc(
                    t.tradeDate.year,
                    t.tradeDate.month,
                    t.tradeDate.day,
                  ).isAfter(
                    DateTime.utc(asOfDate.year, asOfDate.month, asOfDate.day),
                  ),
            )
            .toList()
          ..sort((a, b) {
            final date = a.tradeDate.compareTo(b.tradeDate);
            return date != 0 ? date : (a.id ?? '').compareTo(b.id ?? '');
          });
    if (ordered.any((t) => t.userId.trim().isEmpty) ||
        ordered.map((t) => t.userId).toSet().length > 1) {
      return InvestmentLedgerResult(
        parcels: const [],
        disposals: const [],
        issues: const ['Transactions must belong to one identified user'],
        inputSnapshot: const [],
      );
    }
    final seen = <String>{};
    final sourceIdentities = <String>{};
    for (final t in ordered) {
      applyYearEnd(
        DateTime.utc(t.tradeDate.year, t.tradeDate.month, t.tradeDate.day),
      );
      final id = t.id;
      if (id == null || id.isEmpty || !seen.add(id)) {
        issues.add('Missing or duplicate transaction identity');
        continue;
      }
      snapshots.add({
        'id': id,
        'userId': t.userId,
        'revision': t.revision,
        'sourceHash': t.sourceHash,
        'confirmationNumber': t.confirmationNumber,
        'sourceFileName': t.sourceFileName,
        'sourceParser': t.sourceParser,
        'parserVersion': t.parserVersion,
        'tradeDate': t.tradeDate.toIso8601String(),
        'ticker': t.ticker,
        'accountNumber': t.accountNumber,
        'type': t.direction,
        'units': t.unitsExact,
        'consideration': t.considerationExact,
        'brokerage': t.brokerageExact,
        'totalCost': t.totalCostExact,
        'isReviewed': t.isReviewed,
      });
      try {
        final source = t.confirmationNumber?.trim().isNotEmpty == true
            ? 'confirmation:${t.confirmationNumber!.trim()}'
            : 'hash:${t.sourceHash ?? ''}';
        final identity = '${t.sourceParser}|${t.accountNumber}|$source';
        if (!sourceIdentities.add(identity)) {
          throw const FormatException(
            'Duplicate source fact requires reconciliation',
          );
        }
        if (reviewedFacts &&
            (!t.isReviewed ||
                t.unitsExact == null ||
                t.considerationExact == null ||
                t.brokerageExact == null ||
                t.totalCostExact == null)) {
          throw FormatException('Exact facts must be reviewed');
        }
        if (t.ticker.isEmpty ||
            (t.accountNumber ?? '').isEmpty ||
            (t.sourceHash ?? t.confirmationNumber ?? '').isEmpty) {
          throw FormatException('Missing asset, account or source identity');
        }
        final units = TaxDecimal.parse(t.unitsExact ?? t.units.toString());
        final consideration = TaxDecimal.parse(
          t.considerationExact ?? t.consideration.toString(),
        );
        final brokerage = TaxDecimal.parse(
          t.brokerageExact ?? t.brokerage.toString(),
        );
        final total = TaxDecimal.parse(
          t.totalCostExact ?? t.totalCost.toString(),
        );
        if (units <= TaxDecimal.zero ||
            consideration.isNegative ||
            brokerage.isNegative ||
            total.isNegative) {
          throw FormatException('Invalid quantity or money');
        }
        if (consideration != consideration.rounded() ||
            brokerage != brokerage.rounded() ||
            total != total.rounded()) {
          throw FormatException('Currency precision exceeds cents');
        }
        if (t.isBuy) {
          if (total != consideration + brokerage) {
            throw FormatException(
              'BUY total does not reconcile with consideration plus brokerage',
            );
          }
          parcels[id] = InvestmentParcel(
            buyTransactionId: id,
            ticker: t.ticker,
            accountNumber: t.accountNumber!,
            acquisitionDate: t.tradeDate,
            originalUnits: units,
            remainingUnits: units,
            originalCostBase: total,
            remainingCostBase: total,
            remainingReducedCostBase: total,
          );
          continue;
        }
        if (brokerage > consideration || total != consideration - brokerage) {
          throw FormatException(
            'SELL total does not reconcile with nonnegative net proceeds',
          );
        }
        final matches = allocations
            .where((a) => a.sellTransactionId == id)
            .toList();
        if (matches.length != 1 || matches.single.method != 'specific') {
          throw FormatException(
            'One explicit specific parcel allocation required',
          );
        }
        final allocation = matches.single;
        snapshots.last['allocation'] = allocation.toMap();
        if (allocation.transactionRevisions[id] != t.revision) {
          throw FormatException('Sale allocation revision is stale');
        }
        final chosen = <String>{};
        var selectedUnits = TaxDecimal.zero;
        final staged = <String, InvestmentParcel>{};
        final stagedDisposals = <RealisedDisposal>[];
        final stagedAdjustments = <void Function()>[];
        var allocatedProceeds = TaxDecimal.zero;
        var allocatedFees = TaxDecimal.zero;
        var allocationUnitsRemaining = units;
        for (var index = 0; index < allocation.selections.length; index++) {
          final selection = allocation.selections[index];
          final parcel = parcels[selection.buyTransactionId];
          final buy = ordered
              .where((tx) => tx.id == selection.buyTransactionId)
              .firstOrNull;
          if (!chosen.add(selection.buyTransactionId) ||
              parcel == null ||
              buy == null) {
            throw FormatException('Missing or repeated acquisition');
          }
          if (allocation.transactionRevisions[selection.buyTransactionId] !=
              buy.revision) {
            throw FormatException('Acquisition allocation revision is stale');
          }
          if (parcel.ticker != t.ticker ||
              parcel.accountNumber != t.accountNumber) {
            throw FormatException('Asset/account mismatch');
          }
          final acquiredDay = DateTime.utc(
            parcel.acquisitionDate.year,
            parcel.acquisitionDate.month,
            parcel.acquisitionDate.day,
          );
          final soldDay = DateTime.utc(
            t.tradeDate.year,
            t.tradeDate.month,
            t.tradeDate.day,
          );
          if (!acquiredDay.isBefore(soldDay)) {
            throw FormatException(
              'Same-day or later acquisition requires order evidence',
            );
          }
          final quantity = TaxDecimal.parse(selection.units);
          if (quantity <= TaxDecimal.zero || quantity > parcel.remainingUnits) {
            throw FormatException('Allocation exceeds remaining units');
          }
          selectedUnits += quantity;
          final full = quantity == parcel.remainingUnits;
          final unadjustedBasis = full
              ? parcel.remainingCostBase
              : (parcel.remainingCostBase * quantity).divide(
                  parcel.remainingUnits,
                );
          final unadjustedReduced = full
              ? parcel.remainingReducedCostBase
              : (parcel.remainingReducedCostBase * quantity).divide(
                  parcel.remainingUnits,
                );
          var basis = unadjustedBasis, reduced = unadjustedReduced;
          for (final statement in validStatements) {
            for (final adjustment in statement.adjustments.where(
              (a) =>
                  a.beforeSaleId == id &&
                  a.parcelId == selection.buyTransactionId,
            )) {
              if (statement.ticker != t.ticker ||
                  statement.accountNumber != t.accountNumber ||
                  parseFundDate(adjustment.date) != soldDay ||
                  TaxDecimal.parse(adjustment.units!) != quantity) {
                throw const FormatException(
                  'Pre-disposal adjustment scope does not match sold interest',
                );
              }
              final amount = TaxDecimal.parse(adjustment.amount);
              final openingBasis = basis, openingReduced = reduced;
              basis += amount;
              reduced += TaxDecimal.parse(
                adjustment.reducedAmount ?? adjustment.amount,
              );
              if (basis.isNegative) basis = TaxDecimal.zero;
              if (reduced.isNegative) reduced = TaxDecimal.zero;
              stagedAdjustments.add(
                () => recordAdjustment(
                  statement,
                  adjustment,
                  parcel,
                  openingBasis,
                  openingReduced,
                  amount,
                ),
              );
            }
          }
          final last = index == allocation.selections.length - 1;
          if (quantity > allocationUnitsRemaining) {
            throw FormatException('Allocation exceeds sale quantity');
          }
          final proceeds = last
              ? consideration - allocatedProceeds
              : ((consideration - allocatedProceeds) * quantity).divide(
                  allocationUnitsRemaining,
                );
          final fee = last
              ? brokerage - allocatedFees
              : ((brokerage - allocatedFees) * quantity).divide(
                  allocationUnitsRemaining,
                );
          allocatedProceeds += proceeds;
          allocatedFees += fee;
          allocationUnitsRemaining -= quantity;
          staged[selection.buyTransactionId] = InvestmentParcel(
            buyTransactionId: parcel.buyTransactionId,
            ticker: parcel.ticker,
            accountNumber: parcel.accountNumber,
            acquisitionDate: parcel.acquisitionDate,
            originalUnits: parcel.originalUnits,
            remainingUnits: parcel.remainingUnits - quantity,
            originalCostBase: parcel.originalCostBase,
            remainingCostBase: parcel.remainingCostBase - unadjustedBasis,
            remainingReducedCostBase:
                parcel.remainingReducedCostBase - unadjustedReduced,
          );
          stagedDisposals.add(
            RealisedDisposal(
              sellTransactionId: id,
              buyTransactionId: parcel.buyTransactionId,
              acquisitionDate: parcel.acquisitionDate,
              disposalDate: t.tradeDate,
              units: quantity,
              grossProceeds: proceeds,
              disposalCosts: fee,
              costBase: basis,
              reducedCostBase: reduced,
            ),
          );
        }
        if (selectedUnits != units) {
          throw FormatException(
            'Allocation quantity does not equal sale quantity',
          );
        }
        parcels.addAll(staged);
        disposals.addAll(stagedDisposals);
        for (final apply in stagedAdjustments) {
          apply();
        }
      } on FormatException catch (error) {
        issues.add('$id: ${error.message}');
      }
    }
    applyYearEnd(null);
    for (final statement in validStatements) {
      for (final adjustment in statement.adjustments.where(
        (a) => a.beforeSaleId != null,
      )) {
        final date = parseFundDate(adjustment.date);
        if (asOfDate != null &&
            date.isAfter(
              DateTime.utc(asOfDate.year, asOfDate.month, asOfDate.day),
            )) {
          continue;
        }
        if (!history.any(
          (h) =>
              h['statementId'] == statement.id &&
              h['parcelId'] == adjustment.parcelId &&
              h['beforeSaleId'] == adjustment.beforeSaleId,
        )) {
          issues.add(
            '${statement.id}: Pre-disposal adjustment has no successfully allocated sale',
          );
        }
      }
    }
    for (final allocation in allocations) {
      if (!ordered.any((t) => t.id == allocation.sellTransactionId) &&
          asOfDate == null) {
        issues.add(
          '${allocation.sellTransactionId}: allocation has no source sale',
        );
      }
    }
    return InvestmentLedgerResult(
      statementsSnapshot: statementSnapshots,
      corporateActionsSnapshot: actionSnapshots,
      fundGains: fundGains,
      costBaseHistory: history,
      parcels: List.unmodifiable(parcels.values),
      disposals: List.unmodifiable(disposals),
      issues: List.unmodifiable(issues),
      inputSnapshot: List.unmodifiable(snapshots),
    );
  }
}
