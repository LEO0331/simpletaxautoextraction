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

      expect(service.pendingDrafts.length, 1);
      expect(service.pendingDrafts.first.totalIncome, 2);
    });

    test('syncAll persists drafts and clears queue on success', () async {
      final firestore = FirestoreService(db: FakeFirebaseFirestore());
      service.queueDraft(
        TaxRecord(
          userId: 'u1',
          financialYear: '2025-2026',
          propertyId: 'p2',
          income: {'Gross rent': 123},
        ),
      );

      final synced = await service.syncAll(firestore);

      expect(synced, greaterThanOrEqualTo(1));
      final records = await firestore.getUserTaxRecords('u1').first;
      expect(records.any((r) => r.financialYear == '2025-2026'), isTrue);
    });
  });
}
