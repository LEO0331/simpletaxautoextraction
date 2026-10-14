import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/tax_workspace.dart';

/// Versioned, owner-scoped workpapers. PDF bytes never enter this service.
class TaxWorkspaceService {
  final FirebaseFirestore _db;
  TaxWorkspaceService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);
  DocumentReference<Map<String, dynamic>> _year(String uid, int year) =>
      _user(uid).collection('tax_years').doc('$year');
  DocumentReference<Map<String, dynamic>> _metadata(String uid) =>
      _user(uid).collection('tax_workspace_metadata').doc('current');
  Future<int> getGeneration(String uid) async =>
      ((await _metadata(uid).get()).data()?['generation'] as int?) ?? 0;
  Stream<int> watchGeneration(String uid) => _metadata(
    uid,
  ).snapshots().map((v) => v.data()?['generation'] as int? ?? 0);
  Future<TaxWorkspace?> getWorkspace(String uid, int year) async {
    final value = await _year(uid, year).get();
    return value.exists ? TaxWorkspace.fromMap(value.data()!) : null;
  }

  Future<List<TaxWorkspace>> getWorkspaces(String uid) async =>
      (await _user(uid).collection('tax_years').get()).docs
          .map((doc) => TaxWorkspace.fromMap(doc.data()))
          .toList();

  Future<List<TaxWorkspaceItem>> getItems(String uid, int year) async =>
      (await _year(uid, year).collection('items').get()).docs
          .map((v) => TaxWorkspaceItem.fromMap(v.data(), id: v.id))
          .toList();

  Future<Map<String, dynamic>> getAuditHistory(String uid, int year) async {
    final ref = _year(uid, year);
    final revisions = await ref.collection('revisions').get();
    final items = await ref.collection('items').get();
    final histories = await Future.wait(
      items.docs.map((item) async {
        final versions = await item.reference.collection('revisions').get();
        return MapEntry(
          item.id,
          versions.docs
              .map((version) => {'id': version.id, ...version.data()})
              .toList(),
        );
      }),
    );
    return {
      'workspaceRevisions': revisions.docs
          .map((version) => {'id': version.id, ...version.data()})
          .toList(),
      'itemRevisions': Map.fromEntries(histories),
    };
  }

  Future<List<Map<String, dynamic>>> getSnapshots(
    String uid,
    int year, {
    bool all = false,
  }) async {
    Query<Map<String, dynamic>> query = _year(
      uid,
      year,
    ).collection('snapshots').orderBy('createdAt', descending: true);
    if (!all) query = query.limit(20);
    return (await query.get()).docs
        .map((v) => {'id': v.id, ...v.data()})
        .toList();
  }

  Future<TaxWorkspace> saveWorkspace(
    TaxWorkspace workspace, {
    Map<String, dynamic>? finalSnapshot,
    int? expectedWorkspaceGeneration,
    int? expectedInvestmentGeneration,
  }) async {
    workspace = TaxWorkspace.fromMap(workspace.toMap());
    final issues = workspace.validation();
    if (issues.isNotEmpty) throw FormatException(issues.join('; '));
    if (finalSnapshot != null && workspace.status != 'finalised') {
      throw StateError(
        'Final reports must be archived while finalising a workspace.',
      );
    }
    if (workspace.status == 'finalised' &&
        (finalSnapshot == null ||
            finalSnapshot['report'] is! Map ||
            finalSnapshot['report']['canFinalise'] != true ||
            expectedWorkspaceGeneration == null ||
            expectedInvestmentGeneration == null)) {
      throw StateError(
        'Finalisation requires a fresh reconciled report and source generations.',
      );
    }
    // Copy before asynchronous work so callers cannot mutate the archived report.
    if (finalSnapshot != null &&
        utf8.encode(jsonEncode(finalSnapshot)).length > 900000) {
      throw const FormatException(
        'The workpaper exceeds the supported archive size.',
      );
    }
    final frozen = finalSnapshot == null
        ? null
        : jsonDecode(jsonEncode(finalSnapshot)) as Map<String, dynamic>;
    final ref = _year(workspace.userId, workspace.yearStart);
    final metadata = _metadata(workspace.userId);
    return _db.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final state = await transaction.get(metadata);
      final investment = await transaction.get(
        _user(workspace.userId).collection('investment_metadata').doc('ledger'),
      );
      final revision = current.data()?['revision'] as int? ?? 0;
      final generation = state.data()?['generation'] as int? ?? 0;
      if (revision != workspace.revision ||
          current.data()?['status'] == 'finalised') {
        throw StateError(
          'Workspace changed or is finalised. Reload or amend it.',
        );
      }
      if (frozen != null &&
          (generation != expectedWorkspaceGeneration ||
              (investment.data()?['generation'] as int? ?? 0) !=
                  expectedInvestmentGeneration)) {
        throw StateError(
          'Source records changed. Recalculate before finalising.',
        );
      }
      if (frozen != null &&
          (frozen['report']['workspaceGeneration'] != generation + 1 ||
              frozen['report']['investmentGeneration'] !=
                  expectedInvestmentGeneration ||
              frozen['sourceFingerprint'] !=
                  frozen['report']['sourceFingerprint'])) {
        throw StateError(
          'Report source generations or fingerprint do not match.',
        );
      }
      final data = {
        ...workspace.toMap(),
        'revision': revision + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      transaction.set(ref, data);
      transaction.set(ref.collection('revisions').doc('${revision + 1}'), data);
      transaction.set(metadata, {'generation': generation + 1});
      if (frozen != null) {
        transaction.set(ref.collection('snapshots').doc('${revision + 1}'), {
          'schemaVersion': 1,
          'userId': workspace.userId,
          'yearStart': workspace.yearStart,
          'kind': 'finalised',
          'workspaceRevision': revision + 1,
          'workspaceGeneration': generation + 1,
          'investmentGeneration': expectedInvestmentGeneration,
          'createdAt': FieldValue.serverTimestamp(),
          'payload': frozen,
        });
      }
      return TaxWorkspace.fromMap(data);
    });
  }

  Future<String> saveItem(TaxWorkspaceItem item) async {
    item = TaxWorkspaceItem.fromMap(item.toMap(), id: item.id);
    final issues = item.validation();
    if (issues.isNotEmpty) throw FormatException(issues.join('; '));
    final identity = canonicalTaxFingerprint([
      item.category,
      item.sourceReference.trim(),
    ]);
    if (item.id != null && item.id != identity) {
      throw StateError(
        'An item source identity cannot change. Void it and enter a new source.',
      );
    }
    final year = _year(item.userId, item.yearStart);
    final ref = year.collection('items').doc(identity);
    final metadata = _metadata(item.userId);
    return _db.runTransaction((transaction) async {
      final workspace = await transaction.get(year);
      final current = await transaction.get(ref);
      final state = await transaction.get(metadata);
      if (workspace.data()?['status'] == 'finalised') {
        throw StateError('Amend the finalised year before changing sources.');
      }
      if (!workspace.exists) {
        throw StateError('Save the workspace before adding sources.');
      }
      final revision = current.data()?['revision'] as int? ?? 0;
      final financial = {...item.toMap()}..remove('revision');
      if (current.exists) {
        final existing = {...current.data()!}
          ..remove('revision')
          ..remove('updatedAt');
        if (canonicalTaxFingerprint(existing) ==
            canonicalTaxFingerprint(financial)) {
          return identity;
        }
        if (item.id == null || item.revision != revision) {
          throw StateError(
            'Source already exists or has changed. Open it to correct it.',
          );
        }
      } else if (item.revision != 0) {
        throw StateError('Source no longer exists. Reload it.');
      }
      final data = {
        ...item.toMap(),
        'revision': revision + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      transaction.set(ref, data);
      transaction.set(ref.collection('revisions').doc('${revision + 1}'), data);
      transaction.set(metadata, {
        'generation': (state.data()?['generation'] as int? ?? 0) + 1,
      });
      return identity;
    });
  }

  Future<TaxWorkspace> amendWorkspace(
    String uid,
    int year,
    int expectedRevision,
    String reason,
  ) async {
    if (reason.trim().isEmpty || reason.length > 1000) {
      throw const FormatException('Provide an amendment reason.');
    }
    final ref = _year(uid, year);
    final metadata = _metadata(uid);
    return _db.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final state = await transaction.get(metadata);
      if (current.data()?['status'] != 'finalised' ||
          current.data()?['revision'] != expectedRevision) {
        throw StateError('Reload the finalised workspace before amending.');
      }
      final data = {
        ...current.data()!,
        'status': 'draft',
        'amendmentReason': reason.trim(),
        'revision': expectedRevision + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      transaction.set(ref, data);
      transaction.set(
        ref.collection('revisions').doc('${expectedRevision + 1}'),
        data,
      );
      transaction.set(metadata, {
        'generation': (state.data()?['generation'] as int? ?? 0) + 1,
      });
      return TaxWorkspace.fromMap(data);
    });
  }

  Future<String> importHistoricalSnapshot(
    String uid,
    int year,
    Map<String, dynamic> archive,
  ) async {
    if (utf8.encode(jsonEncode(archive)).length > 900000) {
      throw const FormatException(
        'The historical archive exceeds the supported size.',
      );
    }
    final payload = jsonDecode(jsonEncode(archive)) as Map<String, dynamic>;
    final identity = 'imported-${canonicalTaxFingerprint(payload)}';
    final ref = _year(uid, year);
    final snapshot = ref.collection('snapshots').doc(identity);
    await _db.runTransaction((transaction) async {
      final workspace = await transaction.get(ref);
      final existing = await transaction.get(snapshot);
      if (workspace.data()?['status'] != 'draft') {
        throw StateError('Historical imports require a draft workspace.');
      }
      if (!existing.exists) {
        transaction.set(snapshot, {
          'schemaVersion': 1,
          'kind': 'imported',
          'userId': uid,
          'yearStart': year,
          'createdAt': FieldValue.serverTimestamp(),
          'payload': payload,
        });
      }
    });
    return identity;
  }
}
