import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/screens/investment_transaction_review_screen.dart';
import 'package:simpletaxautoextraction/services/parsers/commsec_trade_confirmation_parser.dart';

void main() {
  const sample = '''
WE HAVE SOLD THE FOLLOWING SECURITIES FOR YOU
EXAMPLE INDEX ETF
SECURITY CODE EXM
TRADE DATE 30/03/2026
TOTAL UNITS 10
AVERAGE PRICE 100
CONSIDERATION (AUD) 1000.00
BROKERAGE & COSTS INCL GST 2.50
NET PROCEEDS 997.50
''';

  Future<void> open(WidgetTester tester, String text) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InvestmentTransactionReviewScreen(
          userId: 'u',
          extraction: CommsecTradeConfirmationParser().parse(text),
        ),
      ),
    );
  }

  Future<void> save(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Save'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
  }

  testWidgets('review rejects sale total that adds brokerage', (tester) async {
    await open(tester, sample.replaceAll('997.50', '1002.50'));
    await save(tester);
    expect(
      find.text(
        'Total must equal gross consideration minus brokerage (GST included).',
      ),
      findsOneWidget,
    );
  });

  testWidgets('review rejects non numeric amount instead of using zero', (
    tester,
  ) async {
    await open(tester, sample);
    final brokerage = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Brokerage (GST included)',
    );
    await tester.scrollUntilVisible(
      brokerage,
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(brokerage, 'NaN');
    await save(tester);
    expect(
      find.text(
        'Enter valid decimals: units and price up to 12 places, money up to 2 places.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('unknown direction requires deliberate selection', (
    tester,
  ) async {
    await open(tester, sample.replaceAll('SOLD', 'TRADED'));
    await save(tester);
    expect(find.text('Explicitly select BUY or SELL.'), findsOneWidget);
  });
}
