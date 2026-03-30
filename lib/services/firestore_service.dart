import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tax_record.dart';

class SaveTaxRecordResult {
  final String documentId;
  final bool replacedExistingYear;

  const SaveTaxRecordResult({
    required this.documentId,
    required this.replacedExistingYear,
  });
}

class FirestoreService {
  final FirebaseFirestore _db;

  FirestoreService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  Future<void> saveTaxRecord(TaxRecord record) async {
    await saveTaxRecordWithStrategy(record);
  }

  Future<SaveTaxRecordResult> saveTaxRecordWithStrategy(
    TaxRecord record, {
    bool saveAsNewYear = false,
    String? overrideFinancialYear,
  }) async {
    final colRef = _db
        .collection('users')
        .doc(record.userId)
        .collection('tax_records');
    final financialYear = overrideFinancialYear ?? record.financialYear;

    if (!saveAsNewYear && record.id != null && record.id!.isNotEmpty) {
      await colRef.doc(record.id).set({
        ...record.copyWith(financialYear: financialYear).toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return SaveTaxRecordResult(
        documentId: record.id!,
        replacedExistingYear: false,
      );
    }

    final duplicate = await colRef
        .where('financialYear', isEqualTo: financialYear)
        .limit(1)
        .get();

    if (duplicate.docs.isNotEmpty && !saveAsNewYear) {
      final existingDoc = duplicate.docs.first;
      await existingDoc.reference.set({
        ...record.copyWith(financialYear: financialYear).toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return SaveTaxRecordResult(
        documentId: existingDoc.id,
        replacedExistingYear: true,
      );
    }

    final newDoc = colRef.doc();
    await newDoc.set({
      ...record.copyWith(id: newDoc.id, financialYear: financialYear).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return SaveTaxRecordResult(
      documentId: newDoc.id,
      replacedExistingYear: false,
    );
  }

  Stream<List<TaxRecord>> getUserTaxRecords(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('tax_records')
        .orderBy('financialYear', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => TaxRecord.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<void> deleteTaxRecord(String userId, String recordId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('tax_records')
        .doc(recordId)
        .delete();
  }
}
