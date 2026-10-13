import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../models/investment_ledger.dart';
import '../models/managed_fund_statement.dart';
import '../models/tax_decimal.dart';
import '../utils/source_fingerprint.dart';
import '../models/investment_transaction.dart';
import 'investment_parcel_ledger.dart';
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

class DuplicateTaxRecordException implements Exception {
  final String financialYear;
  final String propertyName;

  const DuplicateTaxRecordException(this.financialYear, this.propertyName);

  @override
  String toString() =>
      'FY $financialYear already exists for $propertyName. Open that record to update it or choose another year.';
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

    if (duplicate.docs.isNotEmpty && saveAsNewYear) {
      throw DuplicateTaxRecordException(
        financialYear,
        normalizedRecord.propertyName,
      );
    }

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
    for (final isIncome in [true, false]) {
      final mappings = isIncome ? incomeMappings : expenseMappings;
      final categories = isIncome
          ? TaxRecord.incomeCategoryOptions
          : TaxRecord.expenseCategoryOptions;
      for (final rule in mappings.entries) {
        if (rule.key.trim().isEmpty || !categories.contains(rule.value)) {
          throw FormatException(
            'Invalid ${isIncome ? 'income' : 'expense'} mapping: ${rule.key}=${rule.value}',
          );
        }
      }
    }
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
    if (normalizedTransaction.isReviewed && !normalizedTransaction.isVoided) {
      try {
        final values = [
          normalizedTransaction.unitsExact,
          normalizedTransaction.considerationExact,
          normalizedTransaction.brokerageExact,
          normalizedTransaction.totalCostExact,
        ];
        if (values.any((value) => value == null)) throw const FormatException();
        final exact = values.map((value) => TaxDecimal.parse(value!)).toList();
        final legacy = [
          normalizedTransaction.units,
          normalizedTransaction.consideration,
          normalizedTransaction.brokerage,
          normalizedTransaction.totalCost,
        ];
        for (var i = 0; i < legacy.length; i++) {
          if (!legacy[i].isFinite ||
              double.parse(exact[i].toString()) != legacy[i]) {
            throw const FormatException();
          }
        }
        if (exact[0] <= TaxDecimal.zero ||
            exact[1] <= TaxDecimal.zero ||
            exact[2].isNegative ||
            exact[3] <= TaxDecimal.zero ||
            exact[3] !=
                (normalizedTransaction.isBuy
                    ? exact[1] + exact[2]
                    : exact[1] - exact[2])) {
          throw const FormatException();
        }
      } on FormatException {
        throw StateError('Reviewed exact facts must reconcile before saving.');
      }
    }
    final colRef = _db
        .collection('users')
        .doc(normalizedTransaction.userId)
        .collection('investment_transactions');

    final isUpdate = normalizedTransaction.id?.isNotEmpty ?? false;
    // Legacy randomly keyed facts stay untouched; claim their source identity
    // under a transaction so future concurrent imports converge on the same ID.
    final legacyDuplicate = isUpdate
        ? null
        : await findInvestmentDuplicate(
            normalizedTransaction.userId,
            normalizedTransaction,
          );
    final identity = _investmentIdentity(normalizedTransaction);
    final reservation = _db
        .collection('users')
        .doc(transaction.userId)
        .collection('investment_sources')
        .doc(identity);
    final metadata = _ledgerMetadata(transaction.userId);
    return _db.runTransaction((tx) async {
      final source = await tx.get(reservation);
      final ref = colRef.doc(
        isUpdate
            ? normalizedTransaction.id!
            : (source.data()?['transactionId'] as String? ??
                  legacyDuplicate?.id ??
                  identity),
      );
      final existing = await tx.get(ref);
      final meta = await tx.get(metadata);
      if (!isUpdate && existing.exists) {
        final stored = InvestmentTransaction.fromMap(existing.data()!, ref.id);
        final candidate = normalizedTransaction.toMap();
        final previous = stored.toMap();
        const financialKeys = [
          'ticker',
          'transactionType',
          'tradeDate',
          'accountNumber',
          'units',
          'consideration',
          'brokerage',
          'totalCost',
          'unitsExact',
          'considerationExact',
          'brokerageExact',
          'totalCostExact',
        ];
        if (stored.isVoided ||
            financialKeys.any((key) => previous[key] != candidate[key])) {
          throw StateError(
            'Source already exists with different facts. Review and replace explicitly.',
          );
        }
        if (!source.exists) {
          tx.set(reservation, {
            'transactionId': ref.id,
            'userId': transaction.userId,
          });
        }
        return ref.id;
      }
      final old = existing.data();
      if (isUpdate && old == null) {
        throw StateError('Investment transaction no longer exists. Reload.');
      }
      if (old != null &&
          (old['revision'] ?? 0) != normalizedTransaction.revision) {
        throw StateError(
          'Investment transaction changed. Reload before editing.',
        );
      }
      if (old != null && old['isLocked'] == true) {
        final changes = normalizedTransaction.toMap();
        final oldFacts = InvestmentTransaction.fromMap(old, ref.id).toMap();
        for (final key in ['isLocked', 'notes', 'revision']) {
          changes.remove(key);
        }
        if (changes.entries.any(
          (entry) => oldFacts[entry.key] != entry.value,
        )) {
          throw StateError(
            'Unlock the investment before changing financial facts.',
          );
        }
      }
      final revision = old == null ? 1 : (old['revision'] as int? ?? 0) + 1;
      final data = <String, dynamic>{
        ...(old != null && old['isLocked'] == true
            ? old
            : normalizedTransaction.toMap()),
        'isLocked': normalizedTransaction.isLocked,
        'notes': normalizedTransaction.notes,
        'revision': revision,
        'sourceIdentity': old?['sourceIdentity'] ?? identity,
        'createdAt': old?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (old != null &&
          old['isLocked'] == true &&
          !old.containsKey('sourceIdentity')) {
        data.remove('sourceIdentity');
      }
      tx.set(ref, data);
      if (old != null && (old['revision'] ?? 0) == 0) {
        tx.set(ref.collection('revisions').doc('0'), old);
      }
      tx.set(ref.collection('revisions').doc('$revision'), data);
      if (!source.exists) {
        tx.set(reservation, {
          'transactionId': ref.id,
          'userId': transaction.userId,
        });
      } else if (source.data()?['transactionId'] != ref.id) {
        throw StateError('This source already belongs to another transaction.');
      }
      tx.set(metadata, {
        'generation': (meta.data()?['generation'] as int? ?? 0) + 1,
      });
      return ref.id;
    });
  }

  String _investmentIdentity(InvestmentTransaction transaction) {
    final confirmation = transaction.confirmationNumber?.trim() ?? '';
    return SourceFingerprint.text(
      jsonEncode([
        transaction.sourceParser.trim().toLowerCase(),
        transaction.accountNumber?.trim() ?? '',
        if (confirmation.isNotEmpty)
          ['confirmation', confirmation]
        else if (transaction.sourceHash?.isNotEmpty ?? false)
          ['source', transaction.sourceHash]
        else
          [
            'facts',
            transaction.ticker.trim().toUpperCase(),
            transaction.transactionType.value,
            transaction.toMap()['tradeDateIso'],
            transaction.unitsExact ?? transaction.units.toString(),
            transaction.totalCostExact ?? transaction.totalCost.toString(),
          ],
      ]),
    );
  }

  DocumentReference<Map<String, dynamic>> _ledgerMetadata(String userId) => _db
      .collection('users')
      .doc(userId)
      .collection('investment_metadata')
      .doc('ledger');

  Future<int> getInvestmentLedgerGeneration(String userId) async =>
      (await _ledgerMetadata(userId).get()).data()?['generation'] as int? ?? 0;

  Stream<int> watchInvestmentLedgerGeneration(String userId) => _ledgerMetadata(
    userId,
  ).snapshots().map((doc) => doc.data()?['generation'] as int? ?? 0);

  Future<List<ManagedFundStatement>> getManagedFundStatementsOnce(
    String userId, {
    bool includeVoided = false,
  }) async {
    final result = await _db
        .collection('users')
        .doc(userId)
        .collection('managed_fund_statements')
        .get();
    return result.docs
        .map((doc) => ManagedFundStatement.fromMap(doc.data(), id: doc.id))
        .where((statement) => includeVoided || !statement.isVoided)
        .toList();
  }

  /// Corrections replace current facts while preserving immutable source history.
  Future<String> saveManagedFundStatement(
    ManagedFundStatement statement,
  ) async {
    statement = ManagedFundStatement.fromMap({
      ...statement.toMap(),
      'ticker': statement.ticker.trim().toUpperCase(),
      'accountNumber': statement.accountNumber.trim(),
      'issuer': statement.issuer.trim(),
      'layoutVersion': statement.layoutVersion.trim(),
      'sourceReference': statement.sourceReference.trim(),
    }, id: statement.id);
    if (statement.userId.trim().isEmpty) {
      throw StateError('A statement owner is required.');
    }
    final issues = statement.validation();
    if (statement.adjustments.length > 4 || statement.drpLinks.length > 4) {
      throw StateError(
        'A statement supports up to four adjustment slices and four DRP links.',
      );
    }
    if (statement.isReviewed && !statement.isVoided && issues.isNotEmpty) {
      throw StateError(
        'Review statement fields before saving: ${issues.join('; ')}',
      );
    }
    final identity = SourceFingerprint.text(
      jsonEncode([
        statement.accountNumber.trim(),
        statement.ticker.trim().toUpperCase(),
        statement.yearStart,
      ]),
    );
    if (statement.id != null && statement.id != identity) {
      throw StateError(
        'Statement identity changed. Create a separate statement.',
      );
    }
    final generation = await getInvestmentLedgerGeneration(statement.userId);
    if (statement.isReviewed && !statement.isVoided) {
      final facts = await getInvestmentTransactionsOnce(statement.userId);
      final allocations = await getInvestmentAllocationsOnce(statement.userId);
      final previousStatements = await getManagedFundStatementsOnce(
        statement.userId,
      );
      final candidate = ManagedFundStatement.fromMap(
        statement.toMap(),
        id: identity,
      );
      final trial = InvestmentParcelLedger().replay(
        transactions: facts,
        allocations: allocations,
        statements: [
          ...previousStatements.where(
            (old) => old.id != identity && old.isReviewed,
          ),
          candidate,
        ],
      );
      if (trial.issues.any((issue) => issue.startsWith('$identity:'))) {
        throw StateError(
          'Reconcile statement interest, timing and DRP acquisitions before saving.',
        );
      }
    }
    final user = _db.collection('users').doc(statement.userId);
    final ref = user.collection('managed_fund_statements').doc(identity);
    final source = statement.toMap()..remove('id');
    final comparison = Map<String, dynamic>.from(source)..remove('revision');
    await _db.runTransaction((tx) async {
      final existing = await tx.get(ref);
      final meta = await tx.get(_ledgerMetadata(statement.userId));
      final current = existing.data();
      if (current != null) {
        final previous = Map<String, dynamic>.from(current)
          ..remove('revision')
          ..remove('createdAt')
          ..remove('updatedAt');
        if (_sameStatementFacts(previous, comparison)) return;
      }
      if ((current?['revision'] ?? 0) != statement.revision) {
        throw StateError(
          'Statement changed. Reload before saving a correction.',
        );
      }
      if ((meta.data()?['generation'] ?? 0) != generation) {
        throw StateError('Ledger changed. Reload before saving the statement.');
      }
      if (statement.isReviewed && !statement.isVoided) {
        final references = <String>{
          ...statement.adjustments.map((adjustment) => adjustment.parcelId),
          ...statement.drpLinks.map((link) => link.buyTransactionId),
        };
        for (final id in references) {
          final fact = await tx.get(
            user.collection('investment_transactions').doc(id),
          );
          final data = fact.data();
          if (data == null ||
              data['transactionType'] != 'BUY' ||
              data['isVoided'] == true ||
              data['isReviewed'] != true ||
              data['ticker'] != statement.ticker ||
              data['accountNumber'] != statement.accountNumber) {
            throw StateError(
              'Statement parcel and DRP links require matching reviewed acquisitions.',
            );
          }
        }
      }
      final revision = statement.revision + 1;
      final data = <String, dynamic>{
        ...source,
        'revision': revision,
        'createdAt': current?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      tx.set(ref, data);
      tx.set(ref.collection('revisions').doc('$revision'), data);
      tx.set(_ledgerMetadata(statement.userId), {'generation': generation + 1});
    });
    return identity;
  }

  Future<List<Map<String, dynamic>>> getManagedFundStatementRevisionsOnce(
    String userId,
    String statementId,
  ) async {
    final revisions = await _db
        .collection('users')
        .doc(userId)
        .collection('managed_fund_statements')
        .doc(statementId)
        .collection('revisions')
        .orderBy('revision', descending: true)
        .get();
    return revisions.docs
        .map(
          (doc) => <String, dynamic>{
            ...doc.data(),
            'id': doc.id,
            'createdAt': (doc.data()['createdAt'] as Timestamp?)
                ?.toDate()
                .toUtc()
                .toIso8601String(),
            'updatedAt': (doc.data()['updatedAt'] as Timestamp?)
                ?.toDate()
                .toUtc()
                .toIso8601String(),
          },
        )
        .toList();
  }

  bool _sameStatementFacts(Object? left, Object? right) {
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.keys.every(
            (key) =>
                right.containsKey(key) &&
                _sameStatementFacts(left[key], right[key]),
          );
    }
    if (left is List && right is List) {
      return left.length == right.length &&
          List.generate(
            left.length,
            (index) => index,
          ).every((index) => _sameStatementFacts(left[index], right[index]));
    }
    return left == right;
  }

  Future<List<SaleAllocation>> getInvestmentAllocationsOnce(
    String userId,
  ) async {
    final result = await _db
        .collection('users')
        .doc(userId)
        .collection('investment_allocations')
        .get();
    return result.docs
        .map((doc) => SaleAllocation.fromMap(doc.data()))
        .toList();
  }

  Future<void> saveInvestmentAllocation(
    String userId,
    SaleAllocation allocation, {
    int? expectedRevision,
  }) async {
    final previousRevision = expectedRevision ?? allocation.revision;
    final generation = await getInvestmentLedgerGeneration(userId);
    final facts = await getInvestmentTransactionsOnce(userId);
    final currentAllocations = await getInvestmentAllocationsOnce(userId);
    final statements = await getManagedFundStatementsOnce(userId);
    final saleFact = facts
        .where((t) => t.id == allocation.sellTransactionId)
        .firstOrNull;
    if (saleFact == null || !saleFact.isSell || saleFact.isLocked) {
      throw StateError('A current unlocked sale is required.');
    }
    final trial = InvestmentParcelLedger().replay(
      transactions: facts,
      statements: statements
          .where((statement) => statement.isReviewed)
          .toList(),
      allocations: [
        ...currentAllocations.where(
          (a) => a.sellTransactionId != allocation.sellTransactionId,
        ),
        allocation,
      ],
      asOfDate: saleFact.tradeDate,
    );
    if (trial.needsReview) {
      throw StateError(
        'Review facts and quantities before saving parcel selections.',
      );
    }
    final user = _db.collection('users').doc(userId);
    final ref = user
        .collection('investment_allocations')
        .doc(allocation.sellTransactionId);
    final metadata = _ledgerMetadata(userId);
    await _db.runTransaction((tx) async {
      final existing = await tx.get(ref);
      final meta = await tx.get(metadata);
      if ((meta.data()?['generation'] ?? 0) != generation) {
        throw StateError(
          'Ledger changed. Reload before saving parcel selections.',
        );
      }
      if ((existing.data()?['revision'] ?? 0) != previousRevision) {
        throw StateError('Parcel selection changed. Reload before saving.');
      }
      if (!allocation.transactionRevisions.containsKey(
            allocation.sellTransactionId,
          ) ||
          allocation.selections.any(
            (selection) => !allocation.transactionRevisions.containsKey(
              selection.buyTransactionId,
            ),
          )) {
        throw StateError('Parcel selection must include all input revisions.');
      }
      for (final entry in allocation.transactionRevisions.entries) {
        final fact = await tx.get(
          user.collection('investment_transactions').doc(entry.key),
        );
        if (!fact.exists || (fact.data()?['revision'] ?? 0) != entry.value) {
          throw StateError(
            'Investment facts changed. Reload parcel selections.',
          );
        }
      }
      final data = <String, dynamic>{
        ...allocation.toMap(),
        'userId': userId,
        'revision': previousRevision + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final sale = await tx.get(
        user
            .collection('investment_transactions')
            .doc(allocation.sellTransactionId),
      );
      if (sale.data()?['transactionType'] != 'SELL' ||
          sale.data()?['isLocked'] == true ||
          sale.data()?['isVoided'] == true) {
        throw StateError('A current unlocked sale is required.');
      }
      tx.set(ref, data);
      tx.set(ref.collection('revisions').doc('${previousRevision + 1}'), data);
      tx.set(metadata, {
        'generation': (meta.data()?['generation'] as int? ?? 0) + 1,
      });
    });
  }

  Future<String> saveInvestmentCalculationSnapshot(
    String userId,
    Map<String, dynamic> snapshot,
  ) async {
    final user = _db.collection('users').doc(userId);
    final ref = user.collection('investment_calculation_snapshots').doc();
    // Copies freeze the user's reviewed inputs during an asynchronous save.
    snapshot = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(snapshot)) as Map,
    );
    await _db.runTransaction((tx) async {
      final metadata = await tx.get(_ledgerMetadata(userId));
      if (snapshot['ledgerGeneration'] !=
          (metadata.data()?['generation'] ?? 0)) {
        throw StateError(
          'Ledger changed. Recalculate before saving the worksheet.',
        );
      }
      final revisions = Map<String, dynamic>.from(
        snapshot['inputRevisions'] as Map? ?? {},
      );
      if (revisions.isEmpty) {
        final provenance = snapshot['snapshot'] as Map?;
        final context = provenance?['context'] as Map?;
        if (snapshot['schemaVersion'] != 1 ||
            snapshot['inputRevisions'] is! Map ||
            context?['completeHistory'] != true ||
            context?['priorLossesReviewed'] != true ||
            (snapshot['openingLossEvidence'] as String? ?? '').trim().isEmpty) {
          throw StateError(
            'An empty-year snapshot requires reviewed history and loss evidence.',
          );
        }
      }
      for (final entry in revisions.entries) {
        final fact = await tx.get(
          user.collection('investment_transactions').doc(entry.key),
        );
        if (!fact.exists || (fact.data()?['revision'] ?? 0) != entry.value) {
          throw StateError(
            'Investment facts changed. Recalculate the worksheet.',
          );
        }
      }
      final allocationRevisions = Map<String, dynamic>.from(
        snapshot['allocationRevisions'] as Map? ?? {},
      );
      for (final entry in allocationRevisions.entries) {
        final allocation = await tx.get(
          user.collection('investment_allocations').doc(entry.key),
        );
        if (!allocation.exists ||
            allocation.data()?['revision'] != entry.value) {
          throw StateError(
            'Parcel selections changed. Recalculate the worksheet.',
          );
        }
      }
      final statementRevisions = Map<String, dynamic>.from(
        snapshot['statementRevisions'] as Map? ?? {},
      );
      for (final entry in statementRevisions.entries) {
        final statement = await tx.get(
          user.collection('managed_fund_statements').doc(entry.key),
        );
        if (!statement.exists ||
            statement.data()?['revision'] != entry.value ||
            statement.data()?['isVoided'] == true) {
          throw StateError(
            'Fund statements changed. Recalculate the worksheet.',
          );
        }
      }
      tx.set(ref, {
        ...snapshot,
        'userId': userId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    return ref.id;
  }

  Future<List<Map<String, dynamic>>> getInvestmentCalculationSnapshotsOnce(
    String userId,
  ) async {
    final result = await _db
        .collection('users')
        .doc(userId)
        .collection('investment_calculation_snapshots')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();
    return result.docs
        .map(
          (doc) => <String, dynamic>{
            ...doc.data(),
            'id': doc.id,
            'createdAt': (doc.data()['createdAt'] as Timestamp?)
                ?.toDate()
                .toUtc()
                .toIso8601String(),
          },
        )
        .toList();
  }

  Stream<List<InvestmentTransaction>> getInvestmentTransactions(
    String userId, {
    bool includeVoided = false,
  }) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('investment_transactions')
        .orderBy('tradeDate', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => InvestmentTransaction.fromMap(doc.data(), doc.id))
              .where((fact) => includeVoided || !fact.isVoided)
              .toList(),
        );
  }

  Future<List<InvestmentTransaction>> getInvestmentTransactionsOnce(
    String userId, {
    bool includeVoided = false,
  }) async {
    final snapshot = await _db
        .collection('users')
        .doc(userId)
        .collection('investment_transactions')
        .orderBy('tradeDate', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => InvestmentTransaction.fromMap(doc.data(), doc.id))
        .where((fact) => includeVoided || !fact.isVoided)
        .toList();
  }

  Future<void> deleteInvestmentTransaction(
    String userId,
    String recordId,
  ) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('investment_transactions')
        .doc(recordId)
        .get();
    if (!doc.exists) return;
    final fact = InvestmentTransaction.fromMap(doc.data()!, recordId);
    if (fact.isLocked) throw StateError('Unlock the record before voiding it.');
    if (!fact.isVoided) {
      await saveInvestmentTransaction(
        fact.copyWith(isVoided: true, isReviewed: false),
      );
    }
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
          .get();
      for (final doc in byConfirmation.docs) {
        final data = doc.data();
        if ((data['accountNumber'] ?? '') == (candidate.accountNumber ?? '') &&
            data['sourceParser'] == candidate.sourceParser) {
          return InvestmentTransaction.fromMap(data, doc.id);
        }
      }
      // A distinct confirmation is a distinct acquisition, even with equal facts.
      return null;
    }

    final fallback = await colRef
        .where('ticker', isEqualTo: candidate.ticker)
        .where('transactionType', isEqualTo: candidate.transactionType.value)
        .where('units', isEqualTo: candidate.units)
        .where('totalCost', isEqualTo: candidate.totalCost)
        .where('tradeDate', isEqualTo: Timestamp.fromDate(candidate.tradeDate))
        .get();
    for (final doc in fallback.docs) {
      if ((candidate.sourceHash?.isNotEmpty ?? false) &&
          doc.data()['sourceHash'] != null &&
          doc.data()['sourceHash'] != candidate.sourceHash) {
        continue;
      }
      if ((doc.data()['accountNumber'] ?? '') ==
              (candidate.accountNumber ?? '') &&
          doc.data()['sourceParser'] == candidate.sourceParser) {
        return InvestmentTransaction.fromMap(doc.data(), doc.id);
      }
    }
    return null;
  }
}
