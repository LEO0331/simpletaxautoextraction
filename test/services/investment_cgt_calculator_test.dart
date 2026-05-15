import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/investment_transaction.dart';
import 'package:simpletaxautoextraction/services/investment_cgt_calculator.dart';

void main() {
  group('InvestmentCgtCalculator', () {
    test('calculates rows and summary for eligible and non-eligible gains', () {
      const calculator = InvestmentCgtCalculator();
      final oldBuy = InvestmentTransaction(
        userId: 'u1',
        ticker: 'NDQ',
        securityName: 'ETF',
        transactionType: InvestmentTransactionType.buy,
        tradeDate: DateTime(2025, 2, 10),
        units: 80,
        averagePrice: 62.5,
        consideration: 5000,
        brokerage: 0,
        totalCost: 5000,
        sourceParser: 'test',
        parserVersion: 'v1',
      );
      final recentBuy = InvestmentTransaction(
        userId: 'u1',
        ticker: 'VAS',
        securityName: 'ETF',
        transactionType: InvestmentTransactionType.buy,
        tradeDate: DateTime(2026, 1, 10),
        units: 10,
        averagePrice: 100,
        consideration: 1000,
        brokerage: 0,
        totalCost: 1000,
        sourceParser: 'test',
        parserVersion: 'v1',
      );

      final session = calculator.calculate(
        cutOffDate: DateTime(2026, 3, 10),
        tickerPrices: const {'NDQ': 75, 'VAS': 120},
        transactions: [oldBuy, recentBuy],
      );

      expect(session.excludedTransactions, isEmpty);
      expect(session.calculations, hasLength(2));
      expect(session.summary.totalCostBase, closeTo(6000, 0.0001));
      expect(session.summary.totalMarketValueAtCutOff, closeTo(7200, 0.0001));
      expect(session.summary.totalEstimatedGainLoss, closeTo(1200, 0.0001));
      expect(
        session.summary.totalPotentialDiscountEligibleGains,
        closeTo(1000, 0.0001),
      );
      expect(session.summary.totalNotEligibleGains, closeTo(200, 0.0001));
      expect(
        session.summary.totalEstimatedTaxableGainAfterDiscount,
        closeTo(700, 0.0001),
      );
    });

    test('excludes missing price and after cut-off transactions', () {
      const calculator = InvestmentCgtCalculator();
      final transaction = InvestmentTransaction(
        userId: 'u1',
        ticker: 'NDQ',
        securityName: 'ETF',
        transactionType: InvestmentTransactionType.buy,
        tradeDate: DateTime(2026, 4, 10),
        units: 1,
        averagePrice: 100,
        consideration: 100,
        brokerage: 0,
        totalCost: 100,
        sourceParser: 'test',
        parserVersion: 'v1',
      );

      final session = calculator.calculate(
        cutOffDate: DateTime(2026, 3, 10),
        tickerPrices: const {'NDQ': 120},
        transactions: [transaction],
      );

      expect(session.calculations, isEmpty);
      expect(session.excludedTransactions, [transaction]);
      expect(session.summary.totalCostBase, 0);
    });
  });
}
