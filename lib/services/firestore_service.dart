import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/tax_record.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> saveTaxRecord(TaxRecord record) async {
    final colRef = _db.collection('users').doc(record.userId).collection('tax_records');
    
    if (record.id != null && record.id!.isNotEmpty) {
      await colRef.doc(record.id).set(record.toMap());
    } else {
      await colRef.add(record.toMap());
    }
  }

  Stream<List<TaxRecord>> getUserTaxRecords(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('tax_records')
        .orderBy('financialYear', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TaxRecord.fromMap(doc.data(), doc.id))
            .toList());
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
