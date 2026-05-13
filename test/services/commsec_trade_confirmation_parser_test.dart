import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/investment_transaction.dart';
import 'package:simpletaxautoextraction/services/parsers/commsec_trade_confirmation_parser.dart';

void main() {
  test('commsec parser extracts key fields', () {
    const sample = '''
SECURITY
BETASHARES NASDAQ 100 ETF
SECURITY CODE NDQ
BUY
TRADE DATE 30/03/2026
SETTLEMENT DATE 01/04/2026
TOTAL UNITS 80
AVERAGE PRICE 49.660000
CONSIDERATION (AUD) \$3,972.80
BROKERAGE & COSTS INCL GST \$7.94
TOTAL GST \$0.72
TOTAL COST \$3,980.74
CONFIRMATION NO C173462109
ACCOUNT NO 1234567
''';

    final parser = CommsecTradeConfirmationParser();
    final result = parser.parse(sample, sourceFileName: 'C173462109.pdf');
    final d = result.draft;

    expect(d.ticker, 'NDQ');
    expect(d.transactionType, InvestmentTransactionType.buy);
    expect(d.tradeDate, DateTime(2026, 3, 30));
    expect(d.settlementDate, DateTime(2026, 4, 1));
    expect(d.units, closeTo(80, 0.0001));
    expect(d.averagePrice, closeTo(49.66, 0.0001));
    expect(d.consideration, closeTo(3972.80, 0.0001));
    expect(d.brokerage, closeTo(7.94, 0.0001));
    expect(d.gst, closeTo(0.72, 0.0001));
    expect(d.totalCost, closeTo(3980.74, 0.0001));
    expect(d.confirmationNumber, 'C173462109');
  });

  test('commsec parser handles extracted table layout from broker PDF', () {
    const sample = '''
SECURITY:
COMPANY:
WE HAVE BOUGHT THE FOLLOWING SECURITIES FOR YOU
BETASHARES NASDAQ 100 ETF
BETASHARES NASDAQ 100 ETF
NDQ
ORDER COMPLETED
49.660000
AVERAGE PRICE:
UNITS AT PRICE
80
49.660000
PAYMENT METHOD - DIRECT DEBIT OF CLEARED
FUNDS FROM NOMINATED BANK A/C ON
SETTLEMENT DATE.
DATE:
CONFIRMATION NO:
ACCOUNT NO:
TOTAL UNITS:
CONSIDERATION (AUD):
BROKERAGE & COSTS INCL GST:
TOTAL COST:
30/03/2026
30/03/2026
C123456789
1234567
80
3972.80
7.94
3980.74
01/04/2026
0.72
TOTAL GST:
APPLICATION MONEY:
AS AT DATE:
SETTLEMENT DATE:
BUY
TRADE CONFIRMATION
''';

    final parser = CommsecTradeConfirmationParser();
    final result = parser.parse(sample, sourceFileName: 'sample.pdf');
    final d = result.draft;

    expect(d.securityName, 'BETASHARES NASDAQ 100 ETF');
    expect(d.ticker, 'NDQ');
    expect(d.transactionType, InvestmentTransactionType.buy);
    expect(d.tradeDate, DateTime(2026, 3, 30));
    expect(d.settlementDate, DateTime(2026, 4, 1));
    expect(d.units, closeTo(80, 0.0001));
    expect(d.averagePrice, closeTo(49.66, 0.0001));
    expect(d.consideration, closeTo(3972.80, 0.0001));
    expect(d.brokerage, closeTo(7.94, 0.0001));
    expect(d.gst, closeTo(0.72, 0.0001));
    expect(d.totalCost, closeTo(3980.74, 0.0001));
    expect(result.missingFields, isEmpty);
  });

  test('commsec parser marks missing fields', () {
    const sample = 'BUY\nTRADE DATE 30/03/2026\n';
    final parser = CommsecTradeConfirmationParser();
    final result = parser.parse(sample);
    expect(result.missingFields, isNotEmpty);
    expect(result.draft.needsReview, isTrue);
  });
}
