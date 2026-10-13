import '../models/investment_cgt_calculation.dart';
import '../models/investment_cgt_summary.dart';
import '../models/investment_transaction.dart';
import '../models/investment_ledger.dart';
import '../models/tax_decimal.dart';
import '../models/managed_fund_statement.dart';
import 'investment_parcel_ledger.dart';
import '../utils/investment_cgt_utils.dart';

class InvestmentCgtCalculationSession {
  final List<InvestmentCgtCalculation> calculations;
  final InvestmentCgtSummary summary;
  final List<InvestmentTransaction> excludedTransactions;
  final List<String> issues;

  const InvestmentCgtCalculationSession({
    required this.calculations,
    required this.summary,
    required this.excludedTransactions,
    this.issues = const [],
  });
}

class InvestmentCgtCalculator {
  const InvestmentCgtCalculator();

  InvestmentCgtCalculationSession calculate({
    required DateTime cutOffDate,
    required Map<String, double> tickerPrices,
    required List<InvestmentTransaction> transactions,
    List<SaleAllocation> allocations = const [],
    List<ManagedFundStatement> statements = const [],
  }) {
    final calculations = <InvestmentCgtCalculation>[];
    final excluded = <InvestmentTransaction>[];
    final issues = <String>[];
    var holdings = transactions.where((t) => t.isBuy && !t.isVoided).toList();
    final hasSales = transactions.any(
      (t) =>
          t.isSell &&
          !t.isVoided &&
          !DateTime(
            t.tradeDate.year,
            t.tradeDate.month,
            t.tradeDate.day,
          ).isAfter(
            DateTime(cutOffDate.year, cutOffDate.month, cutOffDate.day),
          ),
    );
    final usesLedger = hasSales || statements.any((s) => !s.isVoided);
    if (usesLedger) {
      final ledger = InvestmentParcelLedger().replay(
        transactions: transactions,
        allocations: allocations,
        statements: statements,
        asOfDate: cutOffDate,
      );
      issues.addAll(ledger.issues);
      // Unresolved sales must not leave the disposed units in portfolio totals.
      holdings = ledger.needsReview
          ? []
          : [
              for (final p in ledger.parcels.where(
                (p) => p.remainingUnits > TaxDecimal.zero,
              ))
                transactions
                    .singleWhere((t) => t.id == p.buyTransactionId)
                    .copyWith(
                      units: double.parse(p.remainingUnits.toString()),
                      totalCost: double.parse(p.remainingCostBase.toString()),
                      unitsExact: p.remainingUnits.toString(),
                      totalCostExact: p.remainingCostBase.toString(),
                    ),
            ];
    }

    for (final transaction in holdings) {
      if (!transaction.units.isFinite ||
          transaction.units <= 0 ||
          !transaction.totalCost.isFinite ||
          (usesLedger
              ? transaction.totalCost < 0
              : transaction.totalCost <= 0)) {
        excluded.add(transaction);
        issues.add(
          '${transaction.ticker}: missing or invalid units/cost base; review the transaction.',
        );
        continue;
      }
      final cutOffPrice = tickerPrices[transaction.ticker];
      if (cutOffPrice == null ||
          !cutOffPrice.isFinite ||
          cutOffPrice <= 0 ||
          DateTime.utc(
            cutOffDate.year,
            cutOffDate.month,
            cutOffDate.day,
          ).isBefore(
            DateTime.utc(
              transaction.tradeDate.year,
              transaction.tradeDate.month,
              transaction.tradeDate.day,
            ),
          )) {
        excluded.add(transaction);
        continue;
      }

      final holdingDays = calculateHoldingDays(
        transaction.tradeDate,
        cutOffDate,
      );
      final marketValue = calculateMarketValue(transaction.units, cutOffPrice);
      final gainLoss = calculateGainLoss(marketValue, transaction.totalCost);
      final eligible = RealisedDisposal(
        sellTransactionId: 'estimate',
        buyTransactionId: transaction.id ?? 'estimate',
        acquisitionDate: transaction.tradeDate,
        disposalDate: cutOffDate,
        units: TaxDecimal.zero,
        grossProceeds: TaxDecimal.zero,
        disposalCosts: TaxDecimal.zero,
        costBase: TaxDecimal.zero,
        reducedCostBase: TaxDecimal.zero,
      ).discountEligible;

      calculations.add(
        InvestmentCgtCalculation(
          transaction: transaction,
          cutOffDate: cutOffDate,
          cutOffPrice: cutOffPrice,
          holdingDays: holdingDays,
          marketValueAtCutOff: marketValue,
          estimatedGainLoss: gainLoss,
          gainLossPercent: calculateGainLossPercent(
            gainLoss,
            transaction.totalCost,
          ),
          potentialCgtDiscountEligible: eligible,
          estimatedTaxableGainAfterDiscount:
              calculateEstimatedTaxableGainAfterDiscount(gainLoss, eligible),
        ),
      );
    }

    return InvestmentCgtCalculationSession(
      calculations: List.unmodifiable(calculations),
      summary: _buildSummary(calculations),
      excludedTransactions: List.unmodifiable(excluded),
      issues: List.unmodifiable(issues),
    );
  }

  InvestmentCgtSummary _buildSummary(
    List<InvestmentCgtCalculation> calculations,
  ) {
    double totalCost = 0;
    double totalValue = 0;
    double totalGainLoss = 0;
    double eligibleGains = 0;
    double nonEligibleGains = 0;
    double taxableAfterDiscount = 0;
    double losses = 0;

    for (final calculation in calculations) {
      totalCost += calculation.transaction.totalCost;
      totalValue += calculation.marketValueAtCutOff;
      totalGainLoss += calculation.estimatedGainLoss;
      taxableAfterDiscount += calculation.estimatedTaxableGainAfterDiscount;

      if (calculation.estimatedGainLoss > 0) {
        if (calculation.potentialCgtDiscountEligible) {
          eligibleGains += calculation.estimatedGainLoss;
        } else {
          nonEligibleGains += calculation.estimatedGainLoss;
        }
      } else {
        losses += calculation.estimatedGainLoss.abs();
      }
    }

    return InvestmentCgtSummary(
      totalCostBase: totalCost,
      totalMarketValueAtCutOff: totalValue,
      totalEstimatedGainLoss: totalGainLoss,
      totalPotentialDiscountEligibleGains: eligibleGains,
      totalNotEligibleGains: nonEligibleGains,
      totalEstimatedTaxableGainAfterDiscount: taxableAfterDiscount,
      totalEstimatedCapitalLosses: losses,
    );
  }
}
