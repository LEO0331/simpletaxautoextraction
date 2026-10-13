import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/investment_transaction.dart';
import 'package:simpletaxautoextraction/services/investment_cgt_calculator.dart';
import 'managed_fund_ledger_test.dart' show statement;

InvestmentTransaction acquisition() => InvestmentTransaction(
  id: 'b',
  transactionType: InvestmentTransactionType.buy,
  userId: 'synthetic',
  ticker: 'TEST',
  securityName: 'Synthetic fund',
  tradeDate: DateTime.utc(2022, 1),
  units: 10,
  averagePrice: 1000,
  consideration: 10000,
  brokerage: 0,
  totalCost: 10000,
  unitsExact: '10',
  considerationExact: '10000',
  brokerageExact: '0',
  totalCostExact: '10000',
  isReviewed: true,
  accountNumber: 'synthetic-account',
  confirmationNumber: 'synthetic-buy',
  sourceParser: 'test',
  parserVersion: 'v1',
);

void main() {
  for (final amount in ['300', '-300', '-12000']) {
    test(
      'Unrealised estimate includes historical AMIT $amount without a sale',
      () {
        final result = const InvestmentCgtCalculator().calculate(
          cutOffDate: DateTime.utc(2025, 6, 30),
          tickerPrices: {'TEST': 1100},
          transactions: [acquisition()],
          statements: [statement(amount: amount)],
        );
        expect(result.issues, isEmpty);
        expect(result.calculations, hasLength(1));
        final basis = amount == '300'
            ? 10300.0
            : amount == '-300'
            ? 9700.0
            : 0.0;
        expect(result.summary.totalCostBase, basis);
        expect(result.summary.totalEstimatedGainLoss, 11000 - basis);
      },
    );
  }
  test('Unreviewed statement withholds a complete estimate', () {
    final result = const InvestmentCgtCalculator().calculate(
      cutOffDate: DateTime.utc(2025, 6, 30),
      tickerPrices: {'TEST': 1100},
      transactions: [acquisition()],
      statements: [statement(isReviewed: false)],
    );
    expect(result.issues, isNotEmpty);
    expect(result.calculations, isEmpty);
  });
  test('Earlier cut-off excludes a later historical adjustment', () {
    final result = const InvestmentCgtCalculator().calculate(
      cutOffDate: DateTime.utc(2023, 6, 30),
      tickerPrices: {'TEST': 1100},
      transactions: [acquisition()],
      statements: [statement()],
    );
    expect(result.issues, isEmpty);
    expect(result.summary.totalCostBase, 10000);
  });
}
