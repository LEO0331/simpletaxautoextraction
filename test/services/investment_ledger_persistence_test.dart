import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/investment_ledger.dart';
import 'package:simpletaxautoextraction/models/investment_transaction.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';

InvestmentTransaction fact({
  String account = 'synthetic-account',
  String confirmation = 'synthetic-buy',
  bool sell = false,
}) => InvestmentTransaction(
  userId: 'owner',
  ticker: 'SYN',
  securityName: 'Synthetic security',
  transactionType: sell
      ? InvestmentTransactionType.sell
      : InvestmentTransactionType.buy,
  tradeDate: DateTime(2025, sell ? 6 : 1, 1),
  units: 10,
  averagePrice: 10,
  consideration: 100,
  brokerage: 1,
  totalCost: sell ? 99 : 101,
  accountNumber: account,
  confirmationNumber: confirmation,
  sourceParser: 'Synthetic broker',
  parserVersion: 'v2',
  isReviewed: true,
  unitsExact: '10',
  considerationExact: '100',
  brokerageExact: '1',
  totalCostExact: sell ? '99' : '101',
);

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreService service;
  setUp(() {
    db = FakeFirebaseFirestore();
    service = FirestoreService(db: db);
  });
  test(
    'reviewed zero-activity years retain provenance without fake transactions',
    () async {
      final id = await service.saveInvestmentCalculationSnapshot('owner', {
        'schemaVersion': 1,
        'ledgerGeneration': 0,
        'inputRevisions': <String, int>{},
        'openingLossEvidence':
            'Synthetic verified no activity and zero opening losses',
        'snapshot': {
          'context': {'completeHistory': true, 'priorLossesReviewed': true},
        },
      });
      expect(id, isNotEmpty);
      await expectLater(
        service.saveInvestmentCalculationSnapshot('owner', {
          'schemaVersion': 1,
          'ledgerGeneration': 0,
          'inputRevisions': <String, int>{},
        }),
        throwsStateError,
      );
    },
  );
  test(
    'different confirmations with identical facts remain separate acquisitions',
    () async {
      await service.saveInvestmentTransaction(fact());
      await service.saveInvestmentTransaction(
        fact(confirmation: 'another-synthetic-confirmation'),
      );
      expect(
        await service.getInvestmentTransactionsOnce('owner'),
        hasLength(2),
      );
    },
  );
  test(
    'same source with different reviewed amounts requires explicit correction',
    () async {
      await service.saveInvestmentTransaction(fact());
      await expectLater(
        service.saveInvestmentTransaction(
          fact().copyWith(
            consideration: 200,
            totalCost: 201,
            considerationExact: '200',
            totalCostExact: '201',
          ),
        ),
        throwsStateError,
      );
      expect(
        await service.getInvestmentTransactionsOnce('owner'),
        hasLength(1),
      );
    },
  );

  test(
    'idempotent import reserves a hashed broker/account identity atomically',
    () async {
      final ids = await Future.wait(
        List.generate(3, (_) => service.saveInvestmentTransaction(fact())),
      );
      expect(ids.toSet(), hasLength(1));
      expect(ids.first, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(
        await service.getInvestmentTransactionsOnce('owner'),
        hasLength(1),
      );
      expect(await service.getInvestmentLedgerGeneration('owner'), 1);
      final isolated = await service.saveInvestmentTransaction(
        fact(account: 'other-synthetic-account'),
      );
      expect(isolated, isNot(ids.first));
      expect(
        await service.findInvestmentDuplicate(
          'owner',
          fact(account: 'third-account'),
        ),
        isNull,
      );
    },
  );

  test(
    'edits preserve creation time and immutable revision history; stale edits fail',
    () async {
      final id = await service.saveInvestmentTransaction(fact());
      final original = (await service.getInvestmentTransactionsOnce(
        'owner',
      )).single;
      await service.saveInvestmentTransaction(
        original.copyWith(notes: 'Reviewed synthetic correction'),
      );
      final changed = (await service.getInvestmentTransactionsOnce(
        'owner',
      )).single;
      expect(changed.revision, 2);
      expect(changed.createdAt, original.createdAt);
      expect(
        await db
            .collection('users')
            .doc('owner')
            .collection('investment_transactions')
            .doc(id)
            .collection('revisions')
            .get()
            .then((result) => result.size),
        2,
      );
      await expectLater(
        service.saveInvestmentTransaction(original.copyWith(totalCost: 200)),
        throwsStateError,
      );
    },
  );

  test(
    'locked facts require explicit unlock and voids preserve audit history',
    () async {
      await service.saveInvestmentTransaction(fact().copyWith(isLocked: true));
      final locked = (await service.getInvestmentTransactionsOnce(
        'owner',
      )).single;
      await expectLater(
        service.saveInvestmentTransaction(
          locked.copyWith(units: 20, isLocked: false),
        ),
        throwsStateError,
      );
      await expectLater(
        service.deleteInvestmentTransaction('owner', locked.id!),
        throwsStateError,
      );
      await service.saveInvestmentTransaction(locked.copyWith(isLocked: false));
      final unlocked = (await service.getInvestmentTransactionsOnce(
        'owner',
      )).single;
      await service.saveInvestmentTransaction(
        unlocked.copyWith(units: 20, unitsExact: '20'),
      );
      await service.deleteInvestmentTransaction('owner', locked.id!);
      expect(await service.getInvestmentTransactionsOnce('owner'), isEmpty);
      final audit = (await service.getInvestmentTransactionsOnce(
        'owner',
        includeVoided: true,
      )).single;
      expect(audit.isVoided, isTrue);
      expect(audit.revision, 4);
    },
  );

  test(
    'legacy facts load without mutation and become revisioned only on edit',
    () async {
      final data = fact().toMap()
        ..remove('revision')
        ..remove('isReviewed');
      await db
          .collection('users')
          .doc('owner')
          .collection('investment_transactions')
          .doc('legacy')
          .set(data);
      final legacy = (await service.getInvestmentTransactionsOnce(
        'owner',
      )).single;
      expect(legacy.revision, 0);
      expect(legacy.isReviewed, false);
      await service.saveInvestmentTransaction(
        legacy.copyWith(notes: 'Review required'),
      );
      expect(
        (await db
                .collection('users')
                .doc('owner')
                .collection('investment_transactions')
                .doc('legacy')
                .collection('revisions')
                .doc('0')
                .get())
            .data(),
        data,
      );
      expect(
        (await service.getInvestmentTransactionsOnce('owner')).single.revision,
        1,
      );
    },
  );

  test(
    'allocation revisions reject stale facts and stale selections',
    () async {
      final buyId = await service.saveInvestmentTransaction(fact());
      final sellId = await service.saveInvestmentTransaction(
        fact(confirmation: 'synthetic-sell', sell: true),
      );
      final allocation = SaleAllocation(
        sellTransactionId: sellId,
        selections: [ParcelSelection(buyTransactionId: buyId, units: '10')],
        transactionRevisions: {buyId: 1, sellId: 1},
      );
      await service.saveInvestmentAllocation('owner', allocation);
      final saved = (await service.getInvestmentAllocationsOnce(
        'owner',
      )).single;
      expect(saved.revision, 1);
      await expectLater(
        service.saveInvestmentAllocation('owner', allocation),
        throwsStateError,
      );
      final buy = (await service.getInvestmentTransactionsOnce(
        'owner',
      )).firstWhere((t) => t.id == buyId);
      await service.saveInvestmentTransaction(
        buy.copyWith(notes: 'New evidence'),
      );
      await expectLater(
        service.saveInvestmentAllocation('owner', saved),
        throwsStateError,
      );
    },
  );

  test(
    'snapshot is immutable and any new fact makes prior generation stale',
    () async {
      final id = await service.saveInvestmentTransaction(fact());
      final snapshot = <String, dynamic>{
        'ledgerGeneration': 1,
        'inputRevisions': {id: 1},
        'calculationVersion': 'synthetic-test',
        'issues': <String>[],
      };
      final snapshotId = await service.saveInvestmentCalculationSnapshot(
        'owner',
        snapshot,
      );
      await service.saveInvestmentTransaction(
        fact(confirmation: 'new-synthetic-buy'),
      );
      await expectLater(
        service.saveInvestmentCalculationSnapshot('owner', snapshot),
        throwsStateError,
      );
      final stored = await db
          .collection('users')
          .doc('owner')
          .collection('investment_calculation_snapshots')
          .doc(snapshotId)
          .get();
      expect(stored.data()?['ledgerGeneration'], 1);
      expect(stored.data()?['inputRevisions'], {id: 1});
    },
  );
  test('I1 snapshot rejects missing or stale workspace generation', () async {
    final id = await service.saveInvestmentTransaction(fact());
    final snapshot = <String, dynamic>{
      'ledgerGeneration': 1,
      'inputRevisions': {id: 1},
      'snapshot': {
        'i1Reviews': [
          {'date': '2025-05-01'},
        ],
      },
    };
    await expectLater(
      service.saveInvestmentCalculationSnapshot('owner', snapshot),
      throwsStateError,
    );
    snapshot['workspaceGeneration'] = 0;
    await service.saveInvestmentCalculationSnapshot('owner', snapshot);
    await db
        .collection('users')
        .doc('owner')
        .collection('tax_workspace_metadata')
        .doc('current')
        .set({'generation': 1});
    await expectLater(
      service.saveInvestmentCalculationSnapshot('owner', snapshot),
      throwsStateError,
    );
  });

  test(
    'snapshot verifies corporate action revisions independently of ledger generation',
    () async {
      final id = await service.saveInvestmentTransaction(fact());
      final event = db
          .collection('users')
          .doc('owner')
          .collection('investment_events')
          .doc('synthetic-split');
      await event.set({'revision': 1, 'isVoided': false});
      final snapshot = <String, dynamic>{
        'ledgerGeneration': 1,
        'inputRevisions': {id: 1},
        'corporateActionRevisions': {'synthetic-split': 1},
      };
      await service.saveInvestmentCalculationSnapshot('owner', snapshot);
      await event.update({'revision': 2});
      await expectLater(
        service.saveInvestmentCalculationSnapshot('owner', snapshot),
        throwsStateError,
      );
    },
  );
}
