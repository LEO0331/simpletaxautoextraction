import 'investment_transaction.dart';

class InvestmentCgtCalculation {
  final InvestmentTransaction transaction;
  final DateTime cutOffDate;
  final double cutOffPrice;
  final int holdingDays;
  final double marketValueAtCutOff;
  final double estimatedGainLoss;
  final double gainLossPercent;
  final bool potentialCgtDiscountEligible;
  final double estimatedTaxableGainAfterDiscount;

  const InvestmentCgtCalculation({
    required this.transaction,
    required this.cutOffDate,
    required this.cutOffPrice,
    required this.holdingDays,
    required this.marketValueAtCutOff,
    required this.estimatedGainLoss,
    required this.gainLossPercent,
    required this.potentialCgtDiscountEligible,
    required this.estimatedTaxableGainAfterDiscount,
  });
}
