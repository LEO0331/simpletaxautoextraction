class InvestmentCgtSummary {
  final double totalCostBase;
  final double totalMarketValueAtCutOff;
  final double totalEstimatedGainLoss;
  final double totalPotentialDiscountEligibleGains;
  final double totalNotEligibleGains;
  final double totalEstimatedTaxableGainAfterDiscount;
  final double totalEstimatedCapitalLosses;

  const InvestmentCgtSummary({
    required this.totalCostBase,
    required this.totalMarketValueAtCutOff,
    required this.totalEstimatedGainLoss,
    required this.totalPotentialDiscountEligibleGains,
    required this.totalNotEligibleGains,
    required this.totalEstimatedTaxableGainAfterDiscount,
    required this.totalEstimatedCapitalLosses,
  });
}
