import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/investment_transaction.dart';
import 'package:simpletaxautoextraction/screens/investment_ledger_screen.dart';
import 'package:simpletaxautoextraction/services/auth_service.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';

InvestmentTransaction fixture(bool sale) => InvestmentTransaction(
  userId: 'synthetic-owner',
  ticker: 'SYN',
  securityName: 'Synthetic shares',
  transactionType: sale
      ? InvestmentTransactionType.sell
      : InvestmentTransactionType.buy,
  tradeDate: sale ? DateTime(2026, 1, 2) : DateTime(2024, 1, 1),
  units: sale ? 40 : 100,
  averagePrice: sale ? 15 : 10,
  consideration: sale ? 600 : 1000,
  brokerage: 0,
  totalCost: sale ? 600 : 1000,
  unitsExact: sale ? '40' : '100',
  considerationExact: sale ? '600' : '1000',
  brokerageExact: '0',
  totalCostExact: sale ? '600' : '1000',
  isReviewed: true,
  accountNumber: 'synthetic-account',
  confirmationNumber: sale ? 'synthetic-sell' : 'synthetic-buy',
  sourceParser: 'synthetic-parser',
  parserVersion: 'v1',
);

void main() {
  late FirestoreService store;
  late String buyId;
  late String sellId;
  late MockFirebaseAuth fakeAuth;
  Future<void> open(WidgetTester tester) async {
    store = FirestoreService(db: FakeFirebaseFirestore());
    buyId = await store.saveInvestmentTransaction(fixture(false));
    sellId = await store.saveInvestmentTransaction(fixture(true));
    final auth = fakeAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'synthetic-owner'),
      signedIn: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InvestmentLedgerScreen(
          authService: AuthService(auth: auth),
          firestoreService: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final scrollable = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.scrollUntilVisible(target, 250, scrollable: scrollable);
    await tester.pumpAndSettle();
  }

  testWidgets('missing review confirmations never produce a net capital gain', (
    tester,
  ) async {
    await open(tester);
    await reveal(tester, find.byKey(const Key('calculate-annual')));
    await tester.tap(find.byKey(const Key('calculate-annual')));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('NeedsTaxReview'));
    expect(find.text('NeedsTaxReview'), findsOneWidget);
    expect(find.textContaining('Net capital gain:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit partial sale persists and leaves sixty units', (
    tester,
  ) async {
    await open(tester);
    await reveal(tester, find.byKey(ValueKey('allocate-$sellId')));
    await tester.tap(find.byKey(ValueKey('allocate-$sellId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(ValueKey('parcel-$buyId')), '40');
    await tester.tap(find.text('Save selection'));
    await tester.pumpAndSettle();
    expect(
      (await store.getInvestmentAllocationsOnce(
        'synthetic-owner',
      )).single.selections.single.units,
      '40',
    );
    await reveal(tester, find.text('SYN: 60 units'));
    expect(find.text('SYN: 60 units'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a source revision marks loaded calculations stale', (
    tester,
  ) async {
    await open(tester);
    final buy = (await store.getInvestmentTransactionsOnce(
      'synthetic-owner',
    )).singleWhere((t) => t.id == buyId);
    await store.saveInvestmentTransaction(
      buy.copyWith(notes: 'Reviewed synthetic correction'),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('calculate-annual')));
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const Key('calculate-annual')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('signing out removes the previous account ledger from view', (
    tester,
  ) async {
    await open(tester);
    await fakeAuth.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Please sign in again.'), findsOneWidget);
    expect(find.textContaining('SYN:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
