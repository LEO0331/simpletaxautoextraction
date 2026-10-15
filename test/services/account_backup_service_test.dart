import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/investment_transaction.dart';
import 'package:simpletaxautoextraction/models/managed_fund_statement.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/models/tax_workspace.dart';
import 'package:simpletaxautoextraction/services/account_backup_service.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';
import 'package:simpletaxautoextraction/services/tax_workspace_service.dart';
import 'package:simpletaxautoextraction/services/document_coverage_service.dart';
import 'package:simpletaxautoextraction/services/investment_event_service.dart';
import 'package:simpletaxautoextraction/models/document_coverage.dart';
import 'package:simpletaxautoextraction/models/corporate_action_decision.dart';

void main() {
  late FakeFirebaseFirestore original;
  late String backup;
  late String buyId;
  setUp(() async {
    original = FakeFirebaseFirestore();
    final investments = FirestoreService(db: original);
    buyId = await investments.saveInvestmentTransaction(
      InvestmentTransaction(
        userId: 'owner',
        ticker: 'TEST',
        securityName: 'Synthetic Fund',
        transactionType: InvestmentTransactionType.buy,
        tradeDate: DateTime.utc(2023, 1, 1),
        units: 10,
        averagePrice: 100,
        consideration: 1000,
        brokerage: 10,
        totalCost: 1010,
        unitsExact: '10',
        considerationExact: '1000',
        brokerageExact: '10',
        totalCostExact: '1010',
        accountNumber: 'synthetic-account',
        confirmationNumber: 'synthetic-buy',
        sourceParser: 'Synthetic manual',
        parserVersion: 'synthetic-v1',
        isReviewed: true,
      ),
    );
    await investments.saveManagedFundStatement(
      ManagedFundStatement(
        id: null,
        userId: 'owner',
        ticker: 'TEST',
        accountNumber: 'synthetic-account',
        issuer: 'Synthetic',
        layoutVersion: 'manual-v1',
        yearStart: 2024,
        sourceReference: 'Synthetic annual statement',
        components: {
          for (final key in ManagedFundStatement.componentKeys) key: '0',
        },
      ),
    );
    await investments.saveTaxRecord(
      TaxRecord(
        id: 'rental-one',
        userId: 'owner',
        financialYear: '2024-2025',
        income: {'Gross rent': 2000},
        isLocked: true,
      ),
    );
    await investments.saveProperty(
      'owner',
      const PropertyInfo(id: 'default', name: 'Synthetic property'),
    );
    final workspace = TaxWorkspaceService(db: original);
    await workspace.saveWorkspace(
      const TaxWorkspace(userId: 'owner', yearStart: 2024),
    );
    await workspace.saveItem(
      const TaxWorkspaceItem(
        userId: 'owner',
        yearStart: 2024,
        category: 'salary',
        sourceReference: 'Synthetic employer',
        amount: '1200',
        isReviewed: true,
      ),
    );
    backup = await AccountBackupService(db: original).exportAccount('owner');
  });

  test(
    'inventory and split histories survive recovery without activating reviewed decisions',
    () async {
      await DocumentCoverageService(db: original).save(
        const DocumentCoverage(
          id: 'synthetic-inventory',
          userId: 'owner',
          taxYearStart: 2024,
          account: 'Synthetic broker',
          ticker: 'TEST',
          family: 'fundAnnual',
          state: 'reviewed',
          evidenceReference: 'Synthetic statement',
        ),
        expectedRevision: 0,
      );
      await InvestmentEventService(db: original).saveCorporateAction(
        CorporateActionDecision(
          id: 'synthetic-split',
          userId: 'owner',
          date: '2024-01-01',
          parcelId: buyId,
          oldUnits: '10',
          newUnits: '20',
          evidenceReference: 'Synthetic split',
          reviewed: true,
        ),
      );
      final exported = await AccountBackupService(
        db: original,
      ).exportAccount('owner');
      final destination = FakeFirebaseFirestore();
      final service = AccountBackupService(db: destination);
      final preview = await service.restoreAccount('owner', exported);
      final inventory = await DocumentCoverageService(
        db: destination,
      ).getCoverage('owner', 2024);
      expect(inventory.single.id, 'synthetic-inventory');
      expect(inventory.single.state, 'available');
      expect(
        await InvestmentEventService(
          db: destination,
        ).getCorporateActions('owner'),
        isEmpty,
      );
      final evidence = await service.getRecoveryEvidence('owner', preview.hash);
      expect(
        evidence.any(
          (v) => v['path'] == 'investment_events/synthetic-split/revisions/1',
        ),
        isTrue,
      );
      expect(
        evidence.any(
          (v) =>
              v['path'] == 'document_coverage/synthetic-inventory/revisions/1',
        ),
        isTrue,
      );
      await service.restoreAccount('owner', exported);
    },
  );

  test(
    'full recovery retains IDs, histories and exact draft sources; retry is idempotent',
    () async {
      final destination = FakeFirebaseFirestore();
      final service = AccountBackupService(db: destination);
      final preview = await service.restoreAccount('owner', backup);
      final transactions = await FirestoreService(
        db: destination,
      ).getInvestmentTransactionsOnce('owner');
      expect(transactions.single.id, buyId);
      expect(transactions.single.isReviewed, isFalse);
      expect(transactions.single.isLocked, isFalse);
      expect(transactions.single.totalCostExact, '1010');
      final items = await TaxWorkspaceService(
        db: destination,
      ).getItems('owner', 2024);
      expect(items.single.amount, '1200');
      expect(items.single.isReviewed, isFalse);
      final evidence = await service.getRecoveryEvidence('owner', preview.hash);
      expect(
        evidence.any(
          (v) => v['path'] == 'investment_transactions/$buyId/revisions/1',
        ),
        isTrue,
      );
      expect(
        evidence.any(
          (v) => (v['path'] as String).startsWith('revision_details/'),
        ),
        isTrue,
      );
      await service.restoreAccount('owner', backup);
      expect(await service.getRecoveryIds('owner'), [preview.hash]);
      expect(
        (await FirestoreService(
          db: destination,
        ).getInvestmentTransactionsOnce('owner')).length,
        1,
      );
    },
  );

  test(
    'a consistently rehashed foreign detail family is rejected before any recovery writes',
    () async {
      final changed = jsonDecode(backup) as Map<String, dynamic>;
      final records = (changed['records'] as List).cast<Map>();
      final manifest = records.firstWhere(
        (r) =>
            (r['path'] as String).startsWith('revision_details/') &&
            (r['path'] as String).split('/').length == 2,
      );
      (manifest['data'] as Map)['family'] = 'archive';
      final destination = FakeFirebaseFirestore();
      final service = AccountBackupService(db: destination);
      await expectLater(
        service.restoreAccount('owner', jsonEncode(changed)),
        throwsFormatException,
      );
      expect(await service.getRecoveryIds('owner'), isEmpty);
    },
  );

  test(
    'wrong owner and missing references fail before creating any recovery record',
    () async {
      final destination = FakeFirebaseFirestore();
      final service = AccountBackupService(db: destination);
      await expectLater(
        service.restoreAccount('other', backup),
        throwsFormatException,
      );
      expect(await service.getRecoveryIds('other'), isEmpty);
      final data = jsonDecode(backup) as Map<String, dynamic>;
      (data['records'] as List).removeWhere(
        (r) => r['path'] == 'investment_transactions/$buyId',
      );
      await expectLater(
        service.restoreAccount('owner', jsonEncode(data)),
        throwsFormatException,
      );
      expect(await service.getRecoveryIds('owner'), isEmpty);
    },
  );

  test('live and changed recovered datasets are never overwritten', () async {
    final destination = FakeFirebaseFirestore();
    final service = AccountBackupService(db: destination);
    await TaxWorkspaceService(
      db: destination,
    ).saveWorkspace(const TaxWorkspace(userId: 'owner', yearStart: 2023));
    await expectLater(
      service.restoreAccount('owner', backup),
      throwsStateError,
    );
    expect(await service.getRecoveryIds('owner'), isEmpty);
    final empty = FakeFirebaseFirestore();
    final recovery = AccountBackupService(db: empty);
    await recovery.restoreAccount('owner', backup);
    final store = FirestoreService(db: empty);
    final transaction = (await store.getInvestmentTransactionsOnce(
      'owner',
    )).single;
    await store.saveInvestmentTransaction(
      transaction.copyWith(notes: 'User edit'),
    );
    await expectLater(
      recovery.restoreAccount('owner', backup),
      throwsStateError,
    );
    expect(
      (await store.getInvestmentTransactionsOnce('owner')).single.notes,
      'User edit',
    );
  });

  test(
    'secret fields, unknown paths and invalid timestamp encodings are rejected',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (v) => (v['logical'] as Map)['password'] = 'synthetic',
        (v) => (v['records'] as List).add({'path': 'auth/secrets', 'data': {}}),
        (v) => (v['records'] as List).first['data']['createdAt'] = {
          '__timestamp': [1, -1],
        },
        (v) => (v['records'] as List).first['data']['nested'] = {
          'userId': 'other',
        },
      ]) {
        final data = jsonDecode(backup) as Map<String, dynamic>;
        mutate(data);
        expect(
          () => AccountBackupService.validate(data, 'owner'),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'recovery resumes an interrupted draft activation without changing IDs',
    () async {
      final destination = FakeFirebaseFirestore();
      final decoded = jsonDecode(backup) as Map<String, dynamic>;
      final preview = AccountBackupService.validate(decoded, 'owner');
      await destination
          .collection('users')
          .doc('owner')
          .collection('account_restores')
          .doc(preview.hash)
          .set({
            'schemaVersion': 1,
            'userId': 'owner',
            'backupHash': preview.hash,
            'recordCount': preview.recordCount,
            'createdAt': FieldValue.serverTimestamp(),
          });
      final originalFact = (await FirestoreService(
        db: original,
      ).getInvestmentTransactionsOnce('owner')).single;
      await FirestoreService(db: destination).saveInvestmentTransaction(
        InvestmentTransaction.fromMap({
          ...originalFact.toMap(),
          'isReviewed': false,
          'isLocked': false,
          'revision': 0,
        }, ''),
        creationId: buyId,
      );
      final recovery = AccountBackupService(db: destination);
      await recovery.restoreAccount('owner', backup);
      expect(
        (await FirestoreService(
          db: destination,
        ).getInvestmentTransactionsOnce('owner')).single.id,
        buyId,
      );
      expect(
        (await recovery.getRecoveryEvidence('owner', preview.hash)).length,
        preview.recordCount,
      );
    },
  );

  test('a subsequent full backup retains prior recovery history', () async {
    final destination = FakeFirebaseFirestore();
    final recovery = AccountBackupService(db: destination);
    final first = await recovery.restoreAccount('owner', backup);
    final secondBackup = await recovery.exportAccount('owner');
    final data = jsonDecode(secondBackup) as Map<String, dynamic>;
    final records = data['records'] as List;
    expect(
      records.any((v) => v['path'] == 'account_restores/${first.hash}'),
      isTrue,
    );
    final nextDestination = FakeFirebaseFirestore();
    final next = AccountBackupService(db: nextDestination);
    final second = await next.restoreAccount('owner', secondBackup);
    final evidence = await next.getRecoveryEvidence('owner', second.hash);
    expect(
      evidence.any((v) => v['path'] == 'account_restores/${first.hash}'),
      isTrue,
    );
  });

  test(
    'logical changes and missing detail children fail before evidence upload',
    () async {
      final destination = FakeFirebaseFirestore();
      final recovery = AccountBackupService(db: destination);
      final changed = jsonDecode(backup) as Map<String, dynamic>;
      changed['logical']['transactions'][0]['data']['totalCostExact'] = '999';
      await expectLater(
        recovery.restoreAccount('owner', jsonEncode(changed)),
        throwsFormatException,
      );
      final missing = jsonDecode(backup) as Map<String, dynamic>;
      final manifest = (missing['records'] as List).firstWhere(
        (v) => (v['path'] as String).startsWith('revision_details/'),
      );
      (missing['records'] as List).remove(manifest);
      await expectLater(
        recovery.restoreAccount('owner', jsonEncode(missing)),
        throwsFormatException,
      );
      expect(await recovery.getRecoveryIds('owner'), isEmpty);
    },
  );
}
