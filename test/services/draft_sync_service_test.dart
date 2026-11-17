import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/services/draft_sync_service.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';

void main() {
  group('DraftSyncService', () {
    late DraftSyncService service;

    setUp(() {
      service = DraftSyncService.instance;
      service.clearPendingDrafts();
    });

    test('queues and replaces duplicate drafts', () {
      final first = TaxRecord(
        userId: 'u1',
        financialYear: '2024-2025',
        propertyId: 'p1',
        income: {'Gross rent': 1},
      );
      final second = TaxRecord(
        userId: 'u1',
        financialYear: '2024-2025',
        propertyId: 'p1',
        income: {'Gross rent': 2},
      );

      service.queueDraft(first);
      service.queueDraft(second);

      final pending = service.pendingDraftsFor('u1');
      expect(pending.length, 1);
      expect(pending.first.totalIncome, 2);
    });

    test(
      'syncAll persists and clears only the active owner’s drafts',
      () async {
        final firestore = FirestoreService(db: FakeFirebaseFirestore());
        service.queueDraft(
          TaxRecord(
            userId: 'u1',
            financialYear: '2025-2026',
            propertyId: 'p2',
            income: {'Gross rent': 123},
          ),
        );

        final otherDraft = TaxRecord(userId: 'u2', financialYear: '2025-2026');
        service.queueDraft(otherDraft);

        final synced = await service.syncAll(
          firestore,
          userId: 'u1',
          isCurrentSession: () => true,
        );

        expect(synced, 1);
        expect(service.pendingDraftsFor('u1'), isEmpty);
        expect(service.pendingDraftsFor('u2'), [otherDraft]);
        expect(await firestore.getUserTaxRecords('u2').first, isEmpty);
        final records = await firestore.getUserTaxRecords('u1').first;
        expect(records.any((r) => r.financialYear == '2025-2026'), isTrue);
      },
    );
  });
}
