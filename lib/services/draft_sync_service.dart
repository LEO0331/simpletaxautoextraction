import '../models/tax_record.dart';
import 'firestore_service.dart';

class DraftSyncService {
  DraftSyncService._();
  static final DraftSyncService instance = DraftSyncService._();

  final List<TaxRecord> _pendingDrafts = [];

  List<TaxRecord> pendingDraftsFor(String userId) => List.unmodifiable(
    _pendingDrafts.where((draft) => draft.userId == userId),
  );

  void clearPendingDrafts() {
    _pendingDrafts.clear();
  }

  void queueDraft(TaxRecord record) {
    final existingIndex = _pendingDrafts.indexWhere(
      (draft) =>
          draft.userId == record.userId &&
          draft.financialYear == record.financialYear &&
          draft.propertyId == record.propertyId,
    );
    if (existingIndex >= 0) {
      _pendingDrafts[existingIndex] = record;
    } else {
      _pendingDrafts.add(record);
    }
  }

  Future<int> syncAll(
    FirestoreService firestoreService, {
    required String userId,
    required bool Function() isCurrentSession,
  }) async {
    int synced = 0;
    for (final draft in pendingDraftsFor(userId)) {
      if (!isCurrentSession()) break;
      try {
        await firestoreService.saveTaxRecord(draft);
        _pendingDrafts.remove(draft);
        synced++;
      } catch (_) {
        // Keep unsynced drafts for later retry.
      }
    }
    return synced;
  }
}
