import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/investment_ledger.dart';
import 'package:simpletaxautoextraction/services/investment_cgt_calculator.dart';
import '../screens/investment_ledger_screen_test.dart' show fixture;

void main() {
  test('cut-off comparisons use calendar days rather than instants', () {
    final result = const InvestmentCgtCalculator().calculate(
      cutOffDate: DateTime(2026, 6, 30),
      tickerPrices: {'SYN': 20},
      transactions: [
        fixture(false).copyWith(tradeDate: DateTime.utc(2026, 6, 30, 23, 59)),
      ],
    );
    expect(result.calculations, hasLength(1));
    expect(result.calculations.single.holdingDays, 0);
  });
  test('unrealised estimator uses remaining units and remaining basis', () {
    final buy = fixture(false).copyWith(id: 'buy', revision: 1);
    final sell = fixture(true).copyWith(id: 'sell', revision: 1);
    final result = const InvestmentCgtCalculator().calculate(
      cutOffDate: DateTime(2026, 6, 30),
      tickerPrices: {'SYN': 20},
      transactions: [buy, sell],
      allocations: [
        SaleAllocation(
          sellTransactionId: 'sell',
          transactionRevisions: {'buy': 1, 'sell': 1},
          selections: [
            const ParcelSelection(buyTransactionId: 'buy', units: '40'),
          ],
        ),
      ],
    );
    expect(result.issues, isEmpty);
    expect(result.calculations.single.transaction.units, 60);
    expect(result.summary.totalCostBase, 600);
    expect(result.summary.totalMarketValueAtCutOff, 1200);
  });
  test('unallocated sale cannot leave disposed units in portfolio totals', () {
    final result = const InvestmentCgtCalculator().calculate(
      cutOffDate: DateTime(2026, 6, 30),
      tickerPrices: {'SYN': 20},
      transactions: [
        fixture(false).copyWith(id: 'buy'),
        fixture(true).copyWith(id: 'sell'),
      ],
    );
    expect(result.issues, isNotEmpty);
    expect(result.calculations, isEmpty);
  });
}
