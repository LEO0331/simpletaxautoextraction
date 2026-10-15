import 'package:simpletaxautoextraction/services/revision_detail_store.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/adviser_workpaper_decision.dart';
import 'package:simpletaxautoextraction/models/tax_workspace.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';
import 'package:simpletaxautoextraction/services/tax_workspace_service.dart';
import 'package:simpletaxautoextraction/services/tax_workspace_coordinator.dart';

TaxWorkspace ready(int year) => TaxWorkspace(
  userId: 'owner',
  yearStart: year,
  sectionStates: {for (final k in taxWorkspaceSections) k: 'notApplicable'},
  sectionEvidence: {
    for (final k in taxWorkspaceSections) k: 'Synthetic reviewed absence',
  },
  residencyPeriods: [
    ResidencyPeriod(
      start: '$year-07-01',
      endExclusive: '${year + 1}-07-01',
      classification: 'resident',
      evidence: 'Synthetic evidence',
      reviewed: true,
    ),
  ],
);
AdviserWorkpaperDecision decision(TaxWorkspaceBundle b, {int losses = 0}) =>
    AdviserWorkpaperDecision(
      yearStart: b.workspace.yearStart,
      sourceFingerprint: b.adviserScopeFingerprint,
      adviserReference: 'Synthetic adviser',
      evidenceReference: 'Synthetic workpaper',
      ruleVersion: 'Synthetic reviewed law',
      totals: {...b.report.categoryTotals, 'netCapitalGain': '123.45'},
      reviewed: true,
      completeSources: true,
      closingLossBalances: [
        for (var n = 0; n < losses; n++)
          AdviserClosingLossBalance(
            originStartYear: 2000 + n,
            amount: '10',
            evidenceReference: 'Synthetic origin',
          ),
      ],
    );
void main() {
  late FakeFirebaseFirestore db;
  late TaxWorkspaceService store;
  late TaxWorkspaceCoordinator coordinator;
  setUp(() {
    db = FakeFirebaseFirestore();
    store = TaxWorkspaceService(db: db);
    coordinator = TaxWorkspaceCoordinator(
      workspaces: store,
      sources: FirestoreService(db: db),
    );
  });
  test(
    'adviser scope survives its own save and finalisation, source edits invalidate totals',
    () async {
      await store.saveWorkspace(ready(2024));
      final base = await coordinator.load('owner', 2024);
      await store.saveWorkspace(
        base.workspace.copyWith(adjudication: decision(base, losses: 12)),
      );
      final reviewed = await coordinator.load('owner', 2024);
      expect(reviewed.adviserScopeFingerprint, base.adviserScopeFingerprint);
      expect(reviewed.report.categoryTotals['netCapitalGain'], '123.45');
      expect(reviewed.report.canFinalise, isTrue);
      final raw = (await db.doc('users/owner/tax_years/2024').get()).data()!;
      expect(raw.containsKey('adjudication'), isFalse);
      final rows =
          (await db
                  .collection(
                    'users/owner/revision_details/${raw['detailSetId']}/records',
                  )
                  .get())
              .docs;
      expect(
        rows.where((r) => r.data()['kind'] == 'adjudicationLoss'),
        hasLength(12),
      );
      expect(
        (rows
                    .singleWhere((r) => r.data()['kind'] == 'adjudication')
                    .data()['payload']
                as Map)
            .containsKey('closingLossBalances'),
        isFalse,
      );
      await coordinator.finalise(reviewed);
      final frozen = await coordinator.load('owner', 2024);
      expect(frozen.report.canFinalise, isTrue);
      expect(frozen.adviserScopeFingerprint, base.adviserScopeFingerprint);
      await store.amendWorkspace(
        'owner',
        2024,
        frozen.workspace.revision,
        'Synthetic correction',
      );
      final amended = await coordinator.load('owner', 2024);
      expect(amended.adviserScopeFingerprint, base.adviserScopeFingerprint);
      await store.saveItem(
        const TaxWorkspaceItem(
          userId: 'owner',
          yearStart: 2024,
          category: 'interest',
          sourceReference: 'Synthetic bank',
          amount: '5',
          isReviewed: true,
        ),
      );
      final stale = await coordinator.load('owner', 2024);
      expect(stale.report.canFinalise, isFalse);
      expect(
        stale.report.issues.any(
          (i) => i.contains('Adviser workpaper is stale'),
        ),
        isTrue,
      );
      expect(stale.report.categoryTotals['netCapitalGain'], '0');
    },
  );
  test(
    'prior adviser losses are anchored only while prior sources remain fresh',
    () async {
      await store.saveWorkspace(ready(2023));
      final prior = await coordinator.load('owner', 2023);
      await store.saveWorkspace(
        prior.workspace.copyWith(adjudication: decision(prior, losses: 1)),
      );
      await store.saveWorkspace(ready(2024));
      final later = await coordinator.load('owner', 2024);
      expect(
        (later.auditSources['priorLossAnchor'] as Map)['closingLossBalances'],
        hasLength(1),
      );
      expect(
        later.report.issues.any(
          (i) => i.contains('Prior capital losses require'),
        ),
        isTrue,
      );
      await store.saveItem(
        const TaxWorkspaceItem(
          userId: 'owner',
          yearStart: 2023,
          category: 'interest',
          sourceReference: 'Synthetic correction',
          amount: '1',
          isReviewed: true,
        ),
      );
      final stale = await coordinator.load('owner', 2024);
      expect(
        stale.report.issues.any(
          (i) => i.contains('Earlier capital-loss worksheet'),
        ),
        isTrue,
      );
      expect(
        (stale.auditSources['priorLossAnchor'] as Map)['closingLossBalances'],
        isNull,
      );
    },
  );
  test(
    'orphan and duplicate adviser headers fail closed even with intact hashes',
    () async {
      await store.saveWorkspace(ready(2024));
      final base = await coordinator.load('owner', 2024);
      final header = decision(base).toMap()..remove('closingLossBalances');
      for (final rows in <List<Map<String, dynamic>>>[
        [
          {
            'kind': 'adjudicationLoss',
            'payload': {
              'originStartYear': 2020,
              'amount': '1',
              'evidenceReference': 'Synthetic',
            },
          },
        ],
        [
          {'kind': 'adjudication', 'payload': header},
          {'kind': 'adjudication', 'payload': header},
        ],
      ]) {
        final staged = await RevisionDetailStore(db: db).stage(
          userId: 'owner',
          family: 'workspace',
          subjectId: '2024',
          revision: 1,
          generation: 1,
          yearStart: 2024,
          records: rows,
        );
        await db.doc('users/owner/revision_details/${staged.id}').update({
          'state': 'published',
        });
        await db.doc('users/owner/tax_years/2024').update(staged.fields);
        await expectLater(store.getWorkspace('owner', 2024), throwsStateError);
      }
    },
  );
  test(
    'wrong manifest subject and changed archive attestation fail closed',
    () async {
      await store.saveWorkspace(ready(2024));
      final base = await coordinator.load('owner', 2024);
      final raw = (await db.doc('users/owner/tax_years/2024').get()).data()!;
      await db.doc('users/owner/revision_details/${raw['detailSetId']}').update(
        {'subjectId': '2023'},
      );
      await expectLater(store.getWorkspace('owner', 2024), throwsStateError);
      await db.doc('users/owner/revision_details/${raw['detailSetId']}').update(
        {'subjectId': '2024'},
      );
      await coordinator.finalise(base);
      final archives = await db
          .collection('users/owner/tax_years/2024/snapshots')
          .get();
      await archives.docs.single.reference.update({
        'payloadHeader': {
          'report': {'canFinalise': false},
        },
      });
      await expectLater(store.getSnapshots('owner', 2024), throwsStateError);
    },
  );
  test(
    'legacy finalised amendment preserves schema and all frozen financial fields',
    () async {
      final original = ready(
        2024,
      ).copyWith(status: 'finalised', revision: 1).toMap();
      await db.doc('users/owner/tax_years/2024').set(original);
      await store.amendWorkspace('owner', 2024, 1, 'Synthetic amendment');
      final raw = (await db.doc('users/owner/tax_years/2024').get()).data()!;
      expect(raw['schemaVersion'], 1);
      expect(raw['residencyPeriods'], original['residencyPeriods']);
      final loaded = (await store.getWorkspace('owner', 2024))!;
      await store.saveWorkspace(loaded);
      expect(
        (await db.doc('users/owner/tax_years/2024').get())
            .data()!['schemaVersion'],
        2,
      );
    },
  );
}
