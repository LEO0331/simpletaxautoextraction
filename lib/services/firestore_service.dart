import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/investment_transaction.dart';
import '../models/tax_record.dart';

class SaveTaxRecordResult {
  final String documentId;
  final bool replacedExistingYear;

  const SaveTaxRecordResult({
    required this.documentId,
    required this.replacedExistingYear,
  });
}

class PropertyInfo {
  final String id;
  final String name;

  const PropertyInfo({required this.id, required this.name});
}

class FirestoreService {
  final FirebaseFirestore _db;

  FirestoreService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  TaxRecord _normalizeTaxRecordForWrite(TaxRecord record) {
    final propertyId = record.propertyId.trim().isEmpty
        ? 'default'
        : record.propertyId.trim();
    final propertyName = record.propertyName.trim().isEmpty
        ? 'Primary Property'
        : record.propertyName.trim();
    final notes = record.notes.length > 2000
        ? record.notes.substring(0, 2000)
        : record.notes;
    final parserVersion = record.parserVersion.trim().isEmpty
        ? 'v1'
        : record.parserVersion.trim();

    return record.copyWith(
      propertyId: propertyId,
      propertyName: propertyName,
      notes: notes,
      parserVersion: parserVersion,
      lineItems: List<Map<String, dynamic>>.from(record.lineItems),
    );
  }

  InvestmentTransaction _normalizeInvestmentTransactionForWrite(
    InvestmentTransaction transaction,
  ) {
    return transaction.copyWith(
      ticker: transaction.ticker.trim().toUpperCase(),
      securityName: transaction.securityName.trim(),
      sourceParser: transaction.sourceParser.trim().isEmpty
          ? 'CommSec Trade Confirmation Parser'
          : transaction.sourceParser.trim(),
      parserVersion: transaction.parserVersion.trim().isEmpty
          ? 'v1'
          : transaction.parserVersion.trim(),
      notes: transaction.notes.length > 2000
          ? transaction.notes.substring(0, 2000)
          : transaction.notes,
    );
  }

  Future<void> saveTaxRecord(TaxRecord record) async {
    await saveTaxRecordWithStrategy(record);
  }

  Future<SaveTaxRecordResult> saveTaxRecordWithStrategy(
    TaxRecord record, {
    bool saveAsNewYear = false,
    String? overrideFinancialYear,
  }) async {
    final normalizedRecord = _normalizeTaxRecordForWrite(record);
    final colRef = _db
        .collection('users')
        .doc(normalizedRecord.userId)
        .collection('tax_records');
    final financialYear =
        overrideFinancialYear ?? normalizedRecord.financialYear;

    if (!saveAsNewYear &&
        normalizedRecord.id != null &&
        normalizedRecord.id!.isNotEmpty) {
      await colRef.doc(normalizedRecord.id).set({
        ...normalizedRecord.copyWith(financialYear: financialYear).toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return SaveTaxRecordResult(
        documentId: normalizedRecord.id!,
        replacedExistingYear: false,
      );
    }

    final duplicate = await colRef
        .where('financialYear', isEqualTo: financialYear)
        .where('propertyId', isEqualTo: normalizedRecord.propertyId)
        .limit(1)
        .get();

    if (duplicate.docs.isNotEmpty && !saveAsNewYear) {
      final existingDoc = duplicate.docs.first;
      await existingDoc.reference.set({
        ...normalizedRecord.copyWith(financialYear: financialYear).toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return SaveTaxRecordResult(
        documentId: existingDoc.id,
        replacedExistingYear: true,
      );
    }

    final newDoc = colRef.doc();
    await newDoc.set({
      ...normalizedRecord
          .copyWith(id: newDoc.id, financialYear: financialYear)
          .toMap(),
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

  Future<TaxRecord?> findRecordByYear(
    String userId,
    String financialYear, {
    String? propertyId,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('users')
        .doc(userId)
        .collection('tax_records')
        .where('financialYear', isEqualTo: financialYear);

    if (propertyId != null && propertyId.isNotEmpty) {
      query = query.where('propertyId', isEqualTo: propertyId);
    }

    final snapshot = await query.limit(1).get();
    if (snapshot.docs.isEmpty) {
      return null;
    }
    final doc = snapshot.docs.first;
    return TaxRecord.fromMap(doc.data(), doc.id);
  }

  Future<void> saveCustomMappings(
    String userId,
    Map<String, String> incomeMappings,
    Map<String, String> expenseMappings,
  ) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('mappings')
        .set({
          'income': incomeMappings,
          'expense': expenseMappings,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<Map<String, Map<String, String>>> getCustomMappings(
    String userId,
  ) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('mappings')
        .get();

    final data = doc.data() ?? {};
    return {
      'income': Map<String, String>.from(data['income'] ?? {}),
      'expense': Map<String, String>.from(data['expense'] ?? {}),
    };
  }

  Stream<List<PropertyInfo>> getUserProperties(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('properties')
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => PropertyInfo(
                  id: doc.id,
                  name: doc.data()['name'] ?? 'Unnamed Property',
                ),
              )
              .toList(),
        );
  }

  Future<void> saveProperty(String userId, PropertyInfo property) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('properties')
        .doc(property.id)
        .set({
          'name': property.name,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> deleteTaxRecord(String userId, String recordId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('tax_records')
        .doc(recordId)
        .delete();
  }

  Future<String> saveInvestmentTransaction(
    InvestmentTransaction transaction,
  ) async {
    final normalizedTransaction = _normalizeInvestmentTransactionForWrite(
      transaction,
    );
    final colRef = _db
        .collection('users')
        .doc(normalizedTransaction.userId)
        .collection('investment_transactions');

    if (normalizedTransaction.id != null &&
        normalizedTransaction.id!.isNotEmpty) {
      await colRef.doc(normalizedTransaction.id).set({
        ...normalizedTransaction.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return normalizedTransaction.id!;
    }

    final newDoc = colRef.doc();
    await newDoc.set({
      ...normalizedTransaction.copyWith(id: newDoc.id).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return newDoc.id;
  }

  Stream<List<InvestmentTransaction>> getInvestmentTransactions(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('investment_transactions')
        .orderBy('tradeDate', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => InvestmentTransaction.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<List<InvestmentTransaction>> getInvestmentTransactionsOnce(
    String userId,
  ) async {
    final snapshot = await _db
        .collection('users')
        .doc(userId)
        .collection('investment_transactions')
        .orderBy('tradeDate', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => InvestmentTransaction.fromMap(doc.data(), doc.id))
        .toList();
  }

  Future<void> deleteInvestmentTransaction(
    String userId,
    String recordId,
  ) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('investment_transactions')
        .doc(recordId)
        .delete();
  }

  Future<InvestmentTransaction?> findInvestmentDuplicate(
    String userId,
    InvestmentTransaction candidate,
  ) async {
    final colRef = _db
        .collection('users')
        .doc(userId)
        .collection('investment_transactions');

    if (candidate.confirmationNumber != null &&
        candidate.confirmationNumber!.trim().isNotEmpty) {
      final byConfirmation = await colRef
          .where(
            'confirmationNumber',
            isEqualTo: candidate.confirmationNumber!.trim(),
          )
          .limit(1)
          .get();
      if (byConfirmation.docs.isNotEmpty) {
        final doc = byConfirmation.docs.first;
        return InvestmentTransaction.fromMap(doc.data(), doc.id);
      }
    }

    final fallback = await colRef
        .where('ticker', isEqualTo: candidate.ticker)
        .where('transactionType', isEqualTo: candidate.transactionType.value)
        .where('units', isEqualTo: candidate.units)
        .where('totalCost', isEqualTo: candidate.totalCost)
        .where('tradeDate', isEqualTo: Timestamp.fromDate(candidate.tradeDate))
        .limit(1)
        .get();
    if (fallback.docs.isNotEmpty) {
      final doc = fallback.docs.first;
      return InvestmentTransaction.fromMap(doc.data(), doc.id);
    }
    return null;
  }
}
