import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/corporate_action_decision.dart';
import '../models/document_coverage.dart';

/// Evidenced share-count changes with immutable history and ledger invalidation.
class InvestmentEventService {
  final FirebaseFirestore _db;
  InvestmentEventService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;
  Future<List<CorporateActionDecision>> getCorporateActions(String uid) async =>
      (await getAllCorporateActions(uid)).where((d) => !d.isVoided).toList();
  Future<List<CorporateActionDecision>> getAllCorporateActions(
    String uid,
  ) async =>
      (await _db
              .collection('users')
              .doc(uid)
              .collection('investment_events')
              .get())
          .docs
          .where((d) => d.data()['type'] == 'split')
          .map((d) => CorporateActionDecision.fromMap(d.data(), id: d.id))
          .toList();
  Future<CorporateActionDecision> saveCorporateAction(
    CorporateActionDecision decision, {
    int? expectedRevision,
  }) async {
    final issues = decision.validation();
    if (issues.isNotEmpty) throw FormatException(issues.join('; '));
    if (decision.id.contains('/') || decision.id.length > 128) {
      throw const FormatException('Invalid event identity.');
    }
    final user = _db.collection('users').doc(decision.userId),
        expected = expectedRevision ?? decision.revision;
    final ref = user.collection('investment_events').doc(decision.id),
        meta = user.collection('investment_metadata').doc('ledger'),
        parcel = user
            .collection('investment_transactions')
            .doc(decision.parcelId);
    return _db.runTransaction((tx) async {
      final old = await tx.get(ref),
          state = await tx.get(meta),
          acquisition = await tx.get(parcel);
      if ((old.data()?['revision'] ?? 0) != expected ||
          decision.revision != expected) {
        throw StateError('Corporate action changed. Reload before saving.');
      }
      final buy = acquisition.data();
      if (buy == null ||
          buy['userId'] != decision.userId ||
          buy['transactionType'] != 'BUY' ||
          buy['isVoided'] == true ||
          buy['isReviewed'] != true) {
        throw StateError('Select an active reviewed acquisition.');
      }
      final buyDate = parseDocumentDate(buy['tradeDateIso'] as String? ?? ''),
          eventDate = parseDocumentDate(decision.date);
      if (buyDate == null || eventDate == null || !eventDate.isAfter(buyDate)) {
        throw StateError(
          'Corporate action must occur after the acquisition date.',
        );
      }
      final map = {
        ...decision.toMap(),
        'revision': expected + 1,
        'createdAt': old.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      tx.set(ref, map);
      tx.set(ref.collection('revisions').doc('${expected + 1}'), map);
      tx.set(meta, {
        'generation': (state.data()?['generation'] as int? ?? 0) + 1,
      });
      return CorporateActionDecision.fromMap(map, id: decision.id);
    });
  }
}
