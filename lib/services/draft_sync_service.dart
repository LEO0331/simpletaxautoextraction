import '../models/tax_record.dart';
import 'firestore_service.dart';

class DraftSyncService {
  DraftSyncService._();
  static final DraftSyncService instance = DraftSyncService._();

  final List<TaxRecord> _pendingDrafts = [];

  List<TaxRecord> get pendingDrafts => List.unmodifiable(_pendingDrafts);
  bool get hasPendingDrafts => _pendingDrafts.isNotEmpty;

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

  Future<int> syncAll(FirestoreService firestoreService) async {
    int synced = 0;
    final toRemove = <TaxRecord>[];
    for (final draft in _pendingDrafts) {
      try {
        await firestoreService.saveTaxRecord(draft);
        toRemove.add(draft);
        synced++;
      } catch (_) {
        // Keep unsynced drafts for later retry.
      }
    }
    _pendingDrafts.removeWhere(toRemove.contains);
    return synced;
  }
}
