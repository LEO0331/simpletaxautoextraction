import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_workspace.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';
import 'package:simpletaxautoextraction/services/tax_workspace_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late TaxWorkspaceService service;
  const draft = TaxWorkspace(userId: 'owner', yearStart: 2024);
  const salary = TaxWorkspaceItem(
    userId: 'owner',
    yearStart: 2024,
    category: 'salary',
    sourceReference: 'Synthetic salary',
    amount: '1000',
    isReviewed: true,
  );
  setUp(() {
    db = FakeFirebaseFirestore();
    service = TaxWorkspaceService(db: db);
  });

  Map<String, dynamic> report(int generation) => {
    'sourceFingerprint': 'synthetic-hash',
    'report': {
      'canFinalise': true,
      'workspaceGeneration': generation,
      'investmentGeneration': 0,
      'sourceFingerprint': 'synthetic-hash',
    },
    'sources': {'items': []},
  };
  test(
    'source retries deduplicate, corrections archive and stale editors fail',
    () async {
      await service.saveWorkspace(draft);
      final id = await service.saveItem(salary);
      expect(await service.saveItem(salary), id);
      expect(await service.getGeneration('owner'), 2);
      final old = (await service.getItems('owner', 2024)).single;
      await service.saveItem(old.copyWith(amount: '1100'));
      final history = await service.getAuditHistory('owner', 2024);
      expect((history['workspaceRevisions'] as List).single['revision'], 1);
      final versions = (history['itemRevisions'] as Map)[id] as List;
      expect(versions.map((version) => version['amount']).toSet(), {
        '1000',
        '1100',
      });
      expect(versions.map((version) => version['revision']).toSet(), {1, 2});
      await expectLater(
        service.saveItem(old.copyWith(amount: '1200')),
        throwsStateError,
      );
    },
  );
  test('conflicting source identity requires an explicit correction', () async {
    await service.saveWorkspace(draft);
    await service.saveItem(salary);
    await expectLater(
      service.saveItem(salary.copyWith(amount: '2')),
      throwsStateError,
    );
    expect((await service.getItems('owner', 2024)).single.amount, '1000');
  });
  test(
    'finalisation checks generations, freezes report, blocks edits and requires amendment',
    () async {
      final config = await service.saveWorkspace(draft);
      await service.saveItem(salary);
      await expectLater(
        service.saveWorkspace(
          config.copyWith(status: 'finalised'),
          finalSnapshot: report(3),
          expectedWorkspaceGeneration: 1,
          expectedInvestmentGeneration: 0,
        ),
        throwsStateError,
      );
      final finalised = await service.saveWorkspace(
        config.copyWith(status: 'finalised'),
        finalSnapshot: report(3),
        expectedWorkspaceGeneration: 2,
        expectedInvestmentGeneration: 0,
      );
      expect(finalised.status, 'finalised');
      await expectLater(
        service.saveItem(salary.copyWith(sourceReference: 'Another source')),
        throwsStateError,
      );
      await expectLater(
        service.saveWorkspace(finalised.copyWith(status: 'draft')),
        throwsStateError,
      );
      await expectLater(
        service.amendWorkspace('owner', 2024, finalised.revision, ''),
        throwsFormatException,
      );
      final amended = await service.amendWorkspace(
        'owner',
        2024,
        finalised.revision,
        'Correct salary source',
      );
      expect(amended.status, 'draft');
      expect(
        (await service.getSnapshots(
          'owner',
          2024,
        )).single['workspaceGeneration'],
        3,
      );
      expect(
        (await service.getSnapshots('owner', 2024)).single['payload'],
        report(3),
      );
    },
  );
  test(
    'rental writes advance sources and cannot mutate a finalised year',
    () async {
      final config = await service.saveWorkspace(draft);
      final rentals = FirestoreService(db: db);
      final record = TaxRecord(userId: 'owner', financialYear: '2024-2025');
      final result = await rentals.saveTaxRecordWithStrategy(record);
      expect(await service.getGeneration('owner'), 2);
      await service.saveWorkspace(
        config.copyWith(status: 'finalised'),
        finalSnapshot: report(3),
        expectedWorkspaceGeneration: 2,
        expectedInvestmentGeneration: 0,
      );
      await expectLater(
        rentals.saveTaxRecord(record.copyWith(id: result.documentId)),
        throwsStateError,
      );
      await expectLater(
        rentals.deleteTaxRecord('owner', result.documentId),
        throwsStateError,
      );
      expect(await service.getGeneration('owner'), 3);
    },
  );
  test('historical imports are idempotent, immutable draft archives', () async {
    final config = await service.saveWorkspace(draft);
    final archive = {'synthetic': 'old report'};
    final id = await service.importHistoricalSnapshot('owner', 2024, archive);
    expect(await service.importHistoricalSnapshot('owner', 2024, archive), id);
    expect((await service.getSnapshots('owner', 2024)).length, 1);
    await service.saveWorkspace(
      config.copyWith(status: 'finalised'),
      finalSnapshot: report(2),
      expectedWorkspaceGeneration: 1,
      expectedInvestmentGeneration: 0,
    );
    await expectLater(
      service.importHistoricalSnapshot('owner', 2024, {'another': 'report'}),
      throwsStateError,
    );
  });

  test(
    'investment changes invalidate a freshly reviewed workspace report',
    () async {
      final config = await service.saveWorkspace(draft);
      await db.doc('users/owner/investment_metadata/ledger').set({
        'generation': 1,
      });
      await expectLater(
        service.saveWorkspace(
          config.copyWith(status: 'finalised'),
          finalSnapshot: report(2),
          expectedWorkspaceGeneration: 1,
          expectedInvestmentGeneration: 0,
        ),
        throwsStateError,
      );
      expect((await service.getWorkspace('owner', 2024))!.status, 'draft');
      expect(await service.getGeneration('owner'), 1);
      expect(await service.getSnapshots('owner', 2024), isEmpty);
    },
  );

  test('large archives are chunked and restored exactly', () async {
    final config = await service.saveWorkspace(draft);
    final large = report(2)
      ..['sources'] = {'synthetic': List.filled(1100000, 'a').join()};
    await service.saveWorkspace(
      config.copyWith(status: 'finalised'),
      finalSnapshot: large,
      expectedWorkspaceGeneration: 1,
      expectedInvestmentGeneration: 0,
    );
    expect(await service.getGeneration('owner'), 2);
    final archive = (await service.getSnapshots('owner', 2024)).single;
    expect(archive['payload'], large);
    final raw =
        (await db
                .collection('users')
                .doc('owner')
                .collection('tax_years')
                .doc('2024')
                .collection('snapshots')
                .doc('2')
                .get())
            .data()!;
    expect(raw['schemaVersion'], 2);
    expect(raw.containsKey('payload'), isFalse);
  });
  test(
    'more than four residency and I1 records survive revisions and amendment',
    () async {
      final periods = [
        for (var index = 0; index < 12; index++)
          ResidencyPeriod(
            start: '2024-07-01',
            endExclusive: '2024-08-01',
            classification: 'unknown',
            evidence: 'Synthetic period $index',
          ),
      ];
      final reviews = [
        for (var index = 0; index < 12; index++)
          I1Review(
            date: '2024-08-01',
            assetReference: 'Synthetic asset $index',
          ),
      ];
      var saved = await service.saveWorkspace(
        draft.copyWith(residencyPeriods: periods, i1Reviews: reviews),
      );
      expect((await service.getWorkspace('owner', 2024))!.i1Reviews.length, 12);
      saved = await service.saveWorkspace(
        saved.copyWith(status: 'finalised'),
        finalSnapshot: report(2),
        expectedWorkspaceGeneration: 1,
        expectedInvestmentGeneration: 0,
      );
      final amended = await service.amendWorkspace(
        'owner',
        2024,
        saved.revision,
        'Synthetic correction',
      );
      expect(amended.residencyPeriods.length, 12);
      expect((await service.getWorkspace('owner', 2024))!.i1Reviews.length, 12);
      final history = await service.getAuditHistory('owner', 2024);
      expect((history['workspaceRevisions'] as List).length, 3);
      expect(
        (history['workspaceRevisions'] as List).every(
          (r) => (r['residencyPeriods'] as List).length == 12,
        ),
        isTrue,
      );
    },
  );
  test(
    'incomplete workspace details cannot silently drop reviewed history',
    () async {
      await service.saveWorkspace(
        draft.copyWith(
          residencyPeriods: [
            const ResidencyPeriod(
              start: '2024-07-01',
              endExclusive: '2025-07-01',
              classification: 'resident',
              evidence: 'Synthetic evidence',
              reviewed: true,
            ),
          ],
        ),
      );
      final user = db.collection('users').doc('owner');
      final raw = (await user.collection('tax_years').doc('2024').get())
          .data()!;
      await user
          .collection('revision_details')
          .doc(raw['detailSetId'] as String)
          .collection('records')
          .doc('0')
          .delete();
      await expectLater(service.getWorkspace('owner', 2024), throwsStateError);
      await expectLater(
        service.getAuditHistory('owner', 2024),
        throwsStateError,
      );
    },
  );
}
