import '../models/investment_cgt_calculation.dart';
import '../models/investment_cgt_summary.dart';
import '../models/investment_transaction.dart';
import '../utils/investment_cgt_utils.dart';

class InvestmentCgtCalculationSession {
  final List<InvestmentCgtCalculation> calculations;
  final InvestmentCgtSummary summary;
  final List<InvestmentTransaction> excludedTransactions;

  const InvestmentCgtCalculationSession({
    required this.calculations,
    required this.summary,
    required this.excludedTransactions,
  });
}

class InvestmentCgtCalculator {
  const InvestmentCgtCalculator();

  InvestmentCgtCalculationSession calculate({
    required DateTime cutOffDate,
    required Map<String, double> tickerPrices,
    required List<InvestmentTransaction> transactions,
  }) {
    final calculations = <InvestmentCgtCalculation>[];
    final excluded = <InvestmentTransaction>[];

    for (final transaction in transactions.where((t) => t.isBuy)) {
      final cutOffPrice = tickerPrices[transaction.ticker];
      if (cutOffPrice == null ||
          cutOffPrice <= 0 ||
          cutOffDate.isBefore(transaction.tradeDate)) {
        excluded.add(transaction);
        continue;
      }

      final holdingDays = calculateHoldingDays(
        transaction.tradeDate,
        cutOffDate,
      );
      final marketValue = calculateMarketValue(transaction.units, cutOffPrice);
      final gainLoss = calculateGainLoss(marketValue, transaction.totalCost);
      final eligible = isPotentialCgtDiscountEligible(holdingDays);

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
