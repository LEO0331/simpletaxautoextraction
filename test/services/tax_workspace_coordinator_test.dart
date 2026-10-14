import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_workspace.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/models/managed_fund_statement.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';
import 'package:simpletaxautoextraction/services/tax_workspace_service.dart';
import 'package:simpletaxautoextraction/services/tax_workspace_coordinator.dart';
import 'package:simpletaxautoextraction/services/tax_workspace_calculator.dart';

TaxWorkspace ready(int year) => TaxWorkspace(
  userId: 'owner',
  yearStart: year,
  sectionStates: {for (final key in taxWorkspaceSections) key: 'notApplicable'},
  sectionEvidence: {
    for (final key in taxWorkspaceSections) key: 'Synthetic reviewed absence',
  },
  residencyPeriods: [
    ResidencyPeriod(
      start: '$year-07-01',
      endExclusive: '${year + 1}-07-01',
      classification: 'resident',
      evidence: 'Synthetic adviser evidence',
      reviewed: true,
    ),
  ],
);
TaxWorkspaceItem interest() => const TaxWorkspaceItem(
  userId: 'owner',
  yearStart: 2024,
  category: 'interest',
  sourceReference: 'Synthetic bank statement',
  amount: '12.34',
  isReviewed: true,
);

void main() {
  late FakeFirebaseFirestore db;
  late TaxWorkspaceService store;
  late FirestoreService sources;
  late TaxWorkspaceCoordinator coordinator;
  setUp(() {
    db = FakeFirebaseFirestore();
    store = TaxWorkspaceService(db: db);
    sources = FirestoreService(db: db);
    coordinator = TaxWorkspaceCoordinator(workspaces: store, sources: sources);
  });
  Future<void> lossSnapshot(
    String id,
    int year,
    String closing,
    String opening,
  ) async {
    await db
        .collection('users')
        .doc('owner')
        .collection('investment_calculation_snapshots')
        .doc(id)
        .set({
          'userId': 'owner',
          'year': '$year-${year + 1}',
          'status': 'ReviewedWorksheet',
          'issues': [],
          'ledgerGeneration': 0,
          'netCapitalGain': '0',
          'createdAt': Timestamp.fromDate(DateTime.utc(2026)),
          'snapshot': {
            'context': {
              for (final key in [
                'confirmedContinuousResident',
                'confirmedNonTemporaryResident',
                'completeHistory',
                'noPendingFundAdjustments',
                'priorLossesReviewed',
                'confirmedSupportedAssets',
              ])
                key: true,
              'priorLosses': opening,
              'priorLossBalances': opening == '0'
                  ? []
                  : [
                      {
                        'originStartYear': 2024,
                        'amount': opening,
                        'evidenceReference': 'Synthetic prior workpaper',
                      },
                    ],
            },
            'closingLossBalances': [
              {'originStartYear': year, 'remainingAmount': closing},
            ],
          },
        });
  }

  test(
    'Earlier CGT corrections invalidate opening losses even without changing ledger generation',
    () async {
      await store.saveWorkspace(ready(2024).copyWith(cgtSnapshotId: 'prior'));
      await store.saveWorkspace(ready(2025).copyWith(cgtSnapshotId: 'current'));
      await lossSnapshot('prior', 2024, '100', '0');
      await lossSnapshot('current', 2025, '100', '100');
      final before = await coordinator.load('owner', 2025);
      expect(before.investmentIssues, isEmpty);
      await lossSnapshot('corrected', 2024, '200', '0');
      final prior = (await store.getWorkspace('owner', 2024))!;
      await store.saveWorkspace(prior.copyWith(cgtSnapshotId: 'corrected'));
      final after = await coordinator.load('owner', 2025);
      expect(after.investmentGeneration, before.investmentGeneration);
      expect(
        after.investmentIssues.any(
          (message) => message.contains('no longer match'),
        ),
        isTrue,
      );
      expect(
        after.report.sourceFingerprint,
        isNot(before.report.sourceFingerprint),
      );
    },
  );
  test(
    'Known carried losses require a worksheet even when there is no disposal',
    () async {
      await store.saveWorkspace(ready(2024).copyWith(cgtSnapshotId: 'prior'));
      await store.saveWorkspace(ready(2025));
      await lossSnapshot('prior', 2024, '100', '0');
      final current = await coordinator.load('owner', 2025);
      expect(
        current.investmentIssues.any(
          (message) => message.contains('even with no current disposal'),
        ),
        isTrue,
      );
      expect(current.report.canFinalise, isFalse);
    },
  );
  test(
    'A finalised report matches its own committed generation and stays immutable',
    () async {
      await store.saveWorkspace(ready(2024));
      final bundle = await coordinator.load('owner', 2024);
      expect(bundle.report.canFinalise, isTrue);
      await coordinator.finalise(bundle);
      final current = await coordinator.load('owner', 2024);
      final saved = (await store.getSnapshots('owner', 2024)).single;
      expect(current.workspace.status, 'finalised');
      expect(
        (saved['payload'] as Map)['sourceFingerprint'],
        current.report.sourceFingerprint,
      );
      await expectLater(store.saveItem(interest()), throwsStateError);
      expect(
        (await store.getSnapshots('owner', 2024)).single['id'],
        saved['id'],
      );
    },
  );
  test(
    'Concurrent source changes reject finalisation without archiving stale values',
    () async {
      await store.saveWorkspace(ready(2024));
      final bundle = await coordinator.load('owner', 2024);
      await store.saveItem(interest());
      await expectLater(coordinator.finalise(bundle), throwsStateError);
      expect(await store.getSnapshots('owner', 2024), isEmpty);
    },
  );
  test(
    'Amending an earlier year invalidates later frozen workpapers',
    () async {
      await store.saveWorkspace(ready(2024));
      await coordinator.finalise(await coordinator.load('owner', 2024));
      await store.saveWorkspace(ready(2025));
      await coordinator.finalise(await coordinator.load('owner', 2025));
      final archive = (await store.getSnapshots('owner', 2025)).single;
      final earlier = (await store.getWorkspace('owner', 2024))!;
      await store.amendWorkspace(
        'owner',
        2024,
        earlier.revision,
        'Synthetic amendment',
      );
      final current = await coordinator.load('owner', 2025);
      expect(
        (archive['payload'] as Map)['sourceFingerprint'],
        isNot(current.report.sourceFingerprint),
      );
      expect(current.workspace.status, 'finalised');
      expect(await store.getSnapshots('owner', 2025), hasLength(1));
    },
  );
  Future<String> backupWithSources() async {
    await store.saveWorkspace(
      ready(2024).copyWith(
        sectionStates: {...ready(2024).sectionStates, 'interest': 'reconciled'},
      ),
    );
    await store.saveItem(interest());
    await sources.saveTaxRecord(
      TaxRecord(
        userId: 'owner',
        financialYear: '2024-2025',
        income: {'Gross rent': 100},
        expenses: {'Insurance': 20},
      ),
    );
    await sources.saveManagedFundStatement(
      ManagedFundStatement(
        id: null,
        userId: 'owner',
        ticker: 'SYN',
        accountNumber: 'synthetic',
        issuer: 'Synthetic fund',
        layoutVersion: 'manual-v1',
        yearStart: 2024,
        sourceReference: 'Synthetic annual source',
        isReviewed: true,
        components: {
          for (final key in ManagedFundStatement.componentKeys) key: '0',
          'foreignIncome': '10',
        },
      ),
    );
    return coordinator.exportBackup(await coordinator.load('owner', 2024));
  }

  test(
    'Draft backup restores amounts unreviewed and preserves external sources as immutable evidence',
    () async {
      final text = await backupWithSources();
      final destination = FakeFirebaseFirestore();
      final restoredStore = TaxWorkspaceService(db: destination);
      final restoredSources = FirestoreService(db: destination);
      final restored = TaxWorkspaceCoordinator(
        workspaces: restoredStore,
        sources: restoredSources,
      );
      expect(await restored.restoreBackup('owner', text), 2024);
      final item = (await restoredStore.getItems('owner', 2024)).single;
      expect(item.amount, '12.34');
      expect(item.isReviewed, isFalse);
      final archives = await restoredStore.getSnapshots('owner', 2024);
      expect(archives.single['kind'], 'imported');
      final audit = archives.single['payload'] as Map;
      expect(audit['kind'], 'backup-source-audit');
      expect((audit['sources'] as Map)['rentals'], hasLength(1));
      expect((audit['sources'] as Map)['fundStatements'], hasLength(1));
      expect(
        await restoredSources.getManagedFundStatementsOnce('owner'),
        isEmpty,
      );
      expect((await restored.load('owner', 2024)).report.canFinalise, isFalse);
      final generation = await restoredStore.getGeneration('owner');
      await restored.restoreBackup('owner', text);
      expect(await restoredStore.getItems('owner', 2024), hasLength(1));
      expect(await restoredStore.getSnapshots('owner', 2024), hasLength(1));
      expect(await restoredStore.getGeneration('owner'), generation);
    },
  );
  test(
    'Backup retains immutable original and corrected manual source revisions',
    () async {
      await backupWithSources();
      final original = (await store.getItems('owner', 2024)).single;
      await store.saveItem(original.copyWith(amount: '56.78'));
      final text = await coordinator.exportBackup(
        await coordinator.load('owner', 2024),
      );
      final destination = FakeFirebaseFirestore();
      final restoredStore = TaxWorkspaceService(db: destination);
      final restored = TaxWorkspaceCoordinator(
        workspaces: restoredStore,
        sources: FirestoreService(db: destination),
      );
      await restored.restoreBackup('owner', text);
      final audit =
          (await restoredStore.getSnapshots('owner', 2024)).single['payload']
              as Map;
      final history = audit['history'] as Map;
      final revisions = (history['itemRevisions'] as Map).values.single as List;
      expect(revisions.map((r) => r['amount']).toSet(), {'12.34', '56.78'});
      expect(revisions.map((r) => r['revision']).toSet(), {1, 2});
    },
  );
  test(
    'Wrong owner and corrupted items fail validation before any write',
    () async {
      final text = await backupWithSources();
      final destination = FakeFirebaseFirestore();
      final otherStore = TaxWorkspaceService(db: destination);
      final restored = TaxWorkspaceCoordinator(
        workspaces: otherStore,
        sources: FirestoreService(db: destination),
      );
      await expectLater(
        restored.restoreBackup('other', text),
        throwsFormatException,
      );
      final corrupt = jsonDecode(text) as Map<String, dynamic>;
      (corrupt['items'] as List).first['amount'] = '-1';
      await expectLater(
        restored.restoreBackup('owner', jsonEncode(corrupt)),
        throwsFormatException,
      );
      expect(await otherStore.getWorkspace('owner', 2024), isNull);
      expect(await otherStore.getGeneration('owner'), 0);
    },
  );
  test(
    'Restore cannot overwrite an existing draft or finalised year',
    () async {
      final text = await backupWithSources();
      await expectLater(
        coordinator.restoreBackup('owner', text),
        throwsStateError,
      );
      expect((await store.getItems('owner', 2024)).single.amount, '12.34');
    },
  );
  test(
    'Unsupported future rule years cannot finalise even a zero-source worksheet',
    () {
      final result = TaxWorkspaceCalculator().calculate(
        workspace: ready(2030),
        items: [],
        rentals: [],
        fundStatements: [],
        currentInvestmentGeneration: 0,
        workspaceGeneration: 0,
      );
      expect(result.canFinalise, isFalse);
      expect(
        result.issues,
        contains('Unsupported financial-year rule set requires tax review'),
      );
    },
  );
  test(
    'Older selected CGT archives can still be read after the latest-20 list has moved on',
    () async {
      await store.saveWorkspace(ready(2024).copyWith(cgtSnapshotId: 'older'));
      final collection = db
          .collection('users')
          .doc('owner')
          .collection('investment_calculation_snapshots');
      await collection.doc('older').set({
        'userId': 'owner',
        'year': '2024-2025',
        'createdAt': Timestamp.fromDate(DateTime.utc(2020)),
      });
      for (var i = 0; i < 25; i++) {
        await collection.doc('later-$i').set({
          'userId': 'owner',
          'year': '2025-2026',
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, i + 1)),
        });
      }
      final loaded = await coordinator.load('owner', 2024);
      expect(loaded.cgtSnapshots.any((s) => s['id'] == 'older'), isTrue);
      expect(loaded.report.canFinalise, isFalse);
    },
  );
}
