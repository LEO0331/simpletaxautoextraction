import '../models/investment_transaction.dart';
import 'firestore_service.dart';

class InvestmentDraftSyncService {
  InvestmentDraftSyncService._();
  static final InvestmentDraftSyncService instance =
      InvestmentDraftSyncService._();

  final List<InvestmentTransaction> _pendingDrafts = [];

  List<InvestmentTransaction> get pendingDrafts =>
      List.unmodifiable(_pendingDrafts);
  bool get hasPendingDrafts => _pendingDrafts.isNotEmpty;

  void clearPendingDrafts() {
    _pendingDrafts.clear();
  }

  void queueDraft(InvestmentTransaction transaction) {
    final index = _pendingDrafts.indexWhere(
      (d) =>
          d.userId == transaction.userId &&
          d.ticker == transaction.ticker &&
          d.tradeDate == transaction.tradeDate &&
          d.totalCost == transaction.totalCost &&
          d.transactionType == transaction.transactionType,
    );
    if (index >= 0) {
      _pendingDrafts[index] = transaction;
    } else {
      _pendingDrafts.add(transaction);
    }
  }

  Future<int> syncAll(FirestoreService firestoreService) async {
    int synced = 0;
    final toRemove = <InvestmentTransaction>[];
    for (final d in _pendingDrafts) {
      try {
        await firestoreService.saveInvestmentTransaction(d);
        toRemove.add(d);
        synced++;
      } catch (_) {
        // keep for next retry
      }
    }
    _pendingDrafts.removeWhere(toRemove.contains);
    return synced;
  }
}
