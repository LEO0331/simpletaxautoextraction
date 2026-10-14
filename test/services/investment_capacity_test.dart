import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/investment_ledger.dart';
import 'package:simpletaxautoextraction/models/managed_fund_statement.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';
import 'package:simpletaxautoextraction/services/investment_parcel_ledger.dart';
import 'investment_parcel_ledger_test.dart' show tx, allocation;

void main() {
  test('legacy inline allocation and fund statements still load', () async {
    final db = FakeFirebaseFirestore();
    final service = FirestoreService(db: db);
    final user = db.collection('users').doc('synthetic');
    await user
        .collection('investment_allocations')
        .doc('sale')
        .set(allocation('sale', {'buy': '1'}).toMap());
    final fund = ManagedFundStatement(
      id: 'legacy',
      userId: 'synthetic',
      ticker: 'TEST',
      accountNumber: 'synthetic-account',
      issuer: 'Synthetic',
      layoutVersion: 'legacy',
      yearStart: 2024,
      sourceReference: 'Synthetic',
      components: {for (final k in ManagedFundStatement.componentKeys) k: '0'},
    );
    await user
        .collection('managed_fund_statements')
        .doc('legacy')
        .set(fund.toMap());
    expect(
      (await service.getInvestmentAllocationsOnce(
        'synthetic',
      )).single.selections.single.buyTransactionId,
      'buy',
    );
    expect(
      (await service.getManagedFundStatementsOnce(
        'synthetic',
      )).single.layoutVersion,
      'legacy',
    );
  });

  test(
    'twelve selected parcels conserve sale proceeds and acquisition basis',
    () {
      final buys = [
        for (var i = 0; i < 12; i++)
          tx('b$i', DateTime(2024, 1), units: '1', cash: '100', fee: '0'),
      ];
      final sale = tx(
        'sale',
        DateTime(2025, 1),
        sell: true,
        units: '12',
        cash: '1500',
        fee: '12',
      );
      final ledger = InvestmentParcelLedger().replay(
        transactions: [...buys, sale],
        allocations: [
          allocation('sale', {for (var i = 0; i < 12; i++) 'b$i': '1'}),
        ],
      );
      expect(ledger.issues, isEmpty);
      expect(ledger.disposals, hasLength(12));
      expect(ledger.parcels.every((p) => p.remainingUnits.isZero), isTrue);
      expect(
        ledger.disposals.map((d) => d.capitalGain.toString()),
        everyElement('24'),
      );
    },
  );

  test(
    'twelve parcel allocations roundtrip and missing details fail closed',
    () async {
      final db = FakeFirebaseFirestore();
      final service = FirestoreService(db: db);
      final ids = <String>[];
      for (var i = 0; i < 12; i++) {
        ids.add(
          await service.saveInvestmentTransaction(
            tx(
              'b$i',
              DateTime(2024, 1),
              units: '1',
              cash: '100',
              fee: '0',
            ).copyWith(id: ''),
          ),
        );
      }
      final saleId = await service.saveInvestmentTransaction(
        tx(
          'sale',
          DateTime(2025, 1),
          sell: true,
          units: '12',
          cash: '1500',
          fee: '12',
        ).copyWith(id: ''),
      );
      final facts = await service.getInvestmentTransactionsOnce('synthetic');
      await service.saveInvestmentAllocation(
        'synthetic',
        SaleAllocation(
          sellTransactionId: saleId,
          selections: [
            for (final id in ids)
              ParcelSelection(buyTransactionId: id, units: '1'),
          ],
          transactionRevisions: {for (final f in facts) f.id!: f.revision},
        ),
      );
      final saved = (await service.getInvestmentAllocationsOnce(
        'synthetic',
      )).single;
      expect(saved.selections, hasLength(12));
      final header = db
          .collection('users')
          .doc('synthetic')
          .collection('investment_allocations')
          .doc(saleId);
      expect((await header.get()).data()!.containsKey('selections'), isFalse);
      final original = (await header.get()).data()!;
      await header.update({'detailHash': '0' * 64});
      await expectLater(
        service.getInvestmentAllocationsOnce('synthetic'),
        throwsStateError,
      );
      await header.update({
        'detailHash': original['detailHash'],
        'detailCount': 13,
      });
      await expectLater(
        service.getInvestmentAllocationsOnce('synthetic'),
        throwsStateError,
      );
    },
  );

  test('twelve AMIT slices and DRP links retain correction history', () async {
    final db = FakeFirebaseFirestore();
    final service = FirestoreService(db: db);
    final ids = <String>[];
    for (var i = 0; i < 12; i++) {
      ids.add(
        await service.saveInvestmentTransaction(
          tx(
            'b$i',
            DateTime(2024, 8, 1),
            units: '1',
            cash: '100',
            fee: '0',
          ).copyWith(id: ''),
        ),
      );
    }
    ManagedFundStatement fund({
      String? id,
      int revision = 0,
      bool voided = false,
    }) => ManagedFundStatement(
      id: id,
      userId: 'synthetic',
      ticker: 'TEST',
      accountNumber: 'synthetic-account',
      issuer: 'Synthetic',
      layoutVersion: 'manual',
      yearStart: 2024,
      sourceReference: 'Synthetic only',
      revision: revision,
      isReviewed: true,
      isVoided: voided,
      components: {
        for (final k in ManagedFundStatement.componentKeys) k: '0',
        'amitShortfall': '12',
        'cashDistributions': '1200',
      },
      adjustments: [
        for (final id in ids)
          FundCostBaseAdjustment(
            parcelId: id,
            amount: '1',
            date: '2025-06-30',
            units: '1',
            evidenceReference: 'Synthetic evidence',
          ),
      ],
      drpLinks: [
        for (final id in ids)
          FundDrpLink(
            buyTransactionId: id,
            cashEntitlement: '100',
            reinvestedAmount: '100',
            residualCash: '0',
            evidenceReference: 'Synthetic advice',
          ),
      ],
    );
    final id = await service.saveManagedFundStatement(fund());
    expect(await service.saveManagedFundStatement(fund()), id);
    final current = (await service.getManagedFundStatementsOnce(
      'synthetic',
    )).single;
    expect(current.adjustments, hasLength(12));
    expect(current.drpLinks, hasLength(12));
    await service.saveManagedFundStatement(
      fund(id: id, revision: 1, voided: true),
    );
    final history = await service.getManagedFundStatementRevisionsOnce(
      'synthetic',
      id,
    );
    expect(history, hasLength(2));
    expect(history.last['adjustments'], hasLength(12));
    expect(await service.getManagedFundStatementsOnce('synthetic'), isEmpty);
  });
}
