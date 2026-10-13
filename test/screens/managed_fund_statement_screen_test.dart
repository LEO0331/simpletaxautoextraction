import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/managed_fund_statement.dart';
import 'package:simpletaxautoextraction/models/investment_transaction.dart';
import 'package:simpletaxautoextraction/screens/managed_fund_statement_screen.dart';
import 'package:simpletaxautoextraction/services/auth_service.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';

void main() {
  late FirestoreService store;
  late MockFirebaseAuth auth;
  Future<void> open(WidgetTester tester, {bool seed = true}) async {
    store = FirestoreService(db: FakeFirebaseFirestore());
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'synthetic-owner'),
      signedIn: true,
    );
    if (seed) {
      await store.saveManagedFundStatement(
        ManagedFundStatement(
          id: null,
          userId: 'synthetic-owner',
          ticker: 'SYN',
          accountNumber: 'synthetic-account',
          issuer: 'Synthetic issuer',
          layoutVersion: 'v1',
          yearStart: 2025,
          sourceReference: 'Synthetic statement 2026',
          isReviewed: true,
          components: {
            for (final key in ManagedFundStatement.componentKeys) key: '0',
            'australianIncome': '10',
          },
        ),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: ManagedFundStatementScreen(
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
    await tester.pumpAndSettle();
    for (var i = 0; i < 100 && target.evaluate().isEmpty; i++) {
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(
        (position.pixels + 300).clamp(0, position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  testWidgets('empty statements provide the reviewed manual entry flow', (
    tester,
  ) async {
    await open(tester, seed: false);
    expect(find.text('No managed fund statements yet.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-fund-statement')));
    await tester.pumpAndSettle();
    expect(find.text('Add annual fund statement'), findsOneWidget);
    await reveal(tester, find.byKey(const Key('save-fund-statement')));
    await tester.tap(find.byKey(const Key('save-fund-statement')));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('fund-error')));
    expect(find.textContaining('Statement identity'), findsWidgets);
    expect(
      await store.getManagedFundStatementsOnce('synthetic-owner'),
      isEmpty,
    );
  });

  testWidgets(
    'a deliberate reviewed correction keeps immutable earlier facts',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('SYN · 2025–2026'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const Key('fund-australianIncome')));
      await tester.enterText(
        find.byKey(const Key('fund-australianIncome')),
        '20',
      );
      await reveal(tester, find.byKey(const Key('fund-reviewed')));
      await tester.tap(find.byKey(const Key('fund-reviewed')));
      await reveal(tester, find.byKey(const Key('save-fund-statement')));
      await tester.tap(find.byKey(const Key('save-fund-statement')));
      await tester.pumpAndSettle();
      final saved = (await store.getManagedFundStatementsOnce(
        'synthetic-owner',
      )).single;
      expect(saved.components['australianIncome'], '20');
      expect(saved.revision, 2);
      expect(saved.isReviewed, isTrue);
      final history = await store.getManagedFundStatementRevisionsOnce(
        'synthetic-owner',
        saved.id!,
      );
      expect(history.length, 2);
      expect(
        history.any(
          (r) => (r['components'] as Map)['australianIncome'] == '10',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unreconciled gains do not save even after review confirmation', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('SYN · 2025–2026'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('fund-discountedCapitalGain')));
    await tester.enterText(
      find.byKey(const Key('fund-discountedCapitalGain')),
      '5',
    );
    await reveal(tester, find.byKey(const Key('fund-reviewed')));
    await tester.tap(find.byKey(const Key('fund-reviewed')));
    await reveal(tester, find.byKey(const Key('save-fund-statement')));
    await tester.tap(find.byKey(const Key('save-fund-statement')));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('fund-error')));
    expect(
      find.textContaining('Gross capital gain must reconcile'),
      findsOneWidget,
    );
    expect(
      (await store.getManagedFundStatementsOnce(
        'synthetic-owner',
      )).single.revision,
      1,
    );
  });

  testWidgets('void and reviewed restoration preserve statement history', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('SYN · 2025–2026'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('fund-voided')));
    await tester.tap(find.byKey(const Key('fund-voided')));
    await reveal(tester, find.byKey(const Key('save-fund-statement')));
    await tester.tap(find.byKey(const Key('save-fund-statement')));
    await tester.pumpAndSettle();
    expect(
      await store.getManagedFundStatementsOnce('synthetic-owner'),
      isEmpty,
    );
    final voided = (await store.getManagedFundStatementsOnce(
      'synthetic-owner',
      includeVoided: true,
    )).single;
    expect(voided.revision, 2);
    expect(voided.isVoided, isTrue);
    await tester.tap(find.text('SYN · 2025–2026'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('fund-voided')));
    await tester.tap(find.byKey(const Key('fund-voided')));
    await reveal(tester, find.byKey(const Key('fund-reviewed')));
    await tester.tap(find.byKey(const Key('fund-reviewed')));
    await reveal(tester, find.byKey(const Key('save-fund-statement')));
    await tester.tap(find.byKey(const Key('save-fund-statement')));
    await tester.pumpAndSettle();
    final restored = (await store.getManagedFundStatementsOnce(
      'synthetic-owner',
    )).single;
    expect(restored.revision, 3);
    expect(restored.isReviewed, isTrue);
    expect(
      (await store.getManagedFundStatementRevisionsOnce(
        'synthetic-owner',
        restored.id!,
      )).length,
      3,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-AMIT statements can be captured as unreviewed drafts', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('SYN · 2025–2026'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Non-AMIT').last);
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('save-fund-statement')));
    expect(find.textContaining('NeedsTaxReview: Non-AMIT'), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-fund-statement')));
    await tester.pumpAndSettle();
    final saved = (await store.getManagedFundStatementsOnce(
      'synthetic-owner',
    )).single;
    expect(saved.regime, 'non-AMIT');
    expect(saved.isReviewed, isFalse);
    expect(
      saved.validation(),
      contains('Non-AMIT basis and non-assessable payments require tax review'),
    );
    expect(find.textContaining('NeedsTaxReview · revision 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unreviewed drafts still reject malformed decimal amounts', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('SYN · 2025–2026'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('fund-australianIncome')));
    await tester.enterText(
      find.byKey(const Key('fund-australianIncome')),
      '10x',
    );
    await reveal(tester, find.byKey(const Key('save-fund-statement')));
    await tester.tap(find.byKey(const Key('save-fund-statement')));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('fund-error')));
    expect(
      find.textContaining('Statement amounts must be nonnegative AUD decimals'),
      findsOneWidget,
    );
    expect(
      (await store.getManagedFundStatementsOnce(
        'synthetic-owner',
      )).single.revision,
      1,
    );
  });

  testWidgets('editor exposes copyable reviewed acquisition references', (
    tester,
  ) async {
    await open(tester);
    final buyId = await store.saveInvestmentTransaction(
      InvestmentTransaction(
        userId: 'synthetic-owner',
        ticker: 'SYN',
        securityName: 'Synthetic fund',
        transactionType: InvestmentTransactionType.buy,
        tradeDate: DateTime(2024, 1, 1),
        units: 10,
        averagePrice: 10,
        consideration: 100,
        brokerage: 0,
        totalCost: 100,
        unitsExact: '10',
        considerationExact: '100',
        brokerageExact: '0',
        totalCostExact: '100',
        accountNumber: 'synthetic-account',
        confirmationNumber: 'synthetic-acquisition',
        sourceParser: 'synthetic',
        parserVersion: 'v1',
        isReviewed: true,
      ),
    );
    await tester.tap(find.text('SYN · 2025–2026'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('fund-transaction-references')));
    await tester.tap(find.text('Existing reviewed transaction references'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('ID: $buyId'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(
        SelectableText,
        'BUY SYN · synthetic-account · 2024-01-01 · 10 units\nID: $buyId',
      ),
      findsOneWidget,
    );
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.textContaining('ID: $buyId'), findsNothing);
  });

  testWidgets('sign out clears statements and editor fields', (tester) async {
    await open(tester);
    await tester.tap(find.text('SYN · 2025–2026'));
    await tester.pumpAndSettle();
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Please sign in again.'), findsWidgets);
    expect(find.byKey(const Key('fund-ticker')), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('SYN · 2025–2026'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
