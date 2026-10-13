import '../models/investment_ledger_fact.dart';
import '../models/investment_ledger.dart';
import '../models/tax_decimal.dart';

/// Replays explicit allocations. An invalid sale is atomic and consumes no units.
class InvestmentParcelLedger {
  InvestmentLedgerResult replay({
    required List<InvestmentLedgerFact> transactions,
    required List<SaleAllocation> allocations,
    DateTime? asOfDate,
    bool reviewedFacts = true,
  }) {
    final issues = <String>[];
    final parcels = <String, InvestmentParcel>{};
    final disposals = <RealisedDisposal>[];
    final snapshots = <Map<String, dynamic>>[];
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
        if (allocation.selections.length > 4) {
          throw const FormatException(
            'Phase 1 supports at most four parcels per sale',
          );
        }
        snapshots.last['allocation'] = allocation.toMap();
        if (allocation.transactionRevisions[id] != t.revision) {
          throw FormatException('Sale allocation revision is stale');
        }
        final chosen = <String>{};
        var selectedUnits = TaxDecimal.zero;
        final staged = <String, InvestmentParcel>{};
        final stagedDisposals = <RealisedDisposal>[];
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
          final basis = full
              ? parcel.remainingCostBase
              : (parcel.remainingCostBase * quantity).divide(
                  parcel.remainingUnits,
                );
          final reduced = full
              ? parcel.remainingReducedCostBase
              : (parcel.remainingReducedCostBase * quantity).divide(
                  parcel.remainingUnits,
                );
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
            remainingCostBase: parcel.remainingCostBase - basis,
            remainingReducedCostBase: parcel.remainingReducedCostBase - reduced,
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
      } on FormatException catch (error) {
        issues.add('$id: ${error.message}');
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
      parcels: List.unmodifiable(parcels.values),
      disposals: List.unmodifiable(disposals),
      issues: List.unmodifiable(issues),
      inputSnapshot: List.unmodifiable(snapshots),
    );
  }
}
