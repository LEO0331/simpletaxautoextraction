import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/tax_workspace.dart';
import 'revision_detail_store.dart';
import '../models/document_coverage.dart';
import 'document_coverage_service.dart';

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
  Future<List<DocumentCoverage>> getDocumentCoverage(String uid, int year) =>
      DocumentCoverageService(db: _db).getCoverage(uid, year);

  Future<int> getGeneration(String uid) async =>
      ((await _metadata(uid).get()).data()?['generation'] as int?) ?? 0;
  Stream<int> watchGeneration(String uid) => _metadata(
    uid,
  ).snapshots().map((v) => v.data()?['generation'] as int? ?? 0);
  Future<TaxWorkspace?> getWorkspace(String uid, int year) async {
    final value = await _year(uid, year).get();
    return value.exists
        ? TaxWorkspace.fromMap(await _hydrateWorkspace(uid, value.data()!))
        : null;
  }

  Future<List<TaxWorkspace>> getWorkspaces(String uid) async => Future.wait(
    (await _user(uid).collection('tax_years').get()).docs.map(
      (doc) async =>
          TaxWorkspace.fromMap(await _hydrateWorkspace(uid, doc.data())),
    ),
  );

  Future<Map<String, dynamic>> _hydrateWorkspace(
    String uid,
    Map<String, dynamic> header,
  ) async {
    if (header['schemaVersion'] != 2) return header;
    final records = await RevisionDetailStore(db: _db).read(
      uid,
      header,
      family: 'workspace',
      subjectId: '${header['yearStart']}',
    );
    final adjudications = records
        .where((r) => r['kind'] == 'adjudication')
        .toList();
    final losses = records
        .where((r) => r['kind'] == 'adjudicationLoss')
        .toList();
    if (adjudications.length > 1 ||
        (adjudications.isEmpty && losses.isNotEmpty)) {
      throw StateError('Invalid linked adviser workpaper details.');
    }
    return {
        ...header,
        'schemaVersion': 1,
        if (adjudications.isNotEmpty)
          'adjudication': {
            ...Map<String, dynamic>.from(
              adjudications.single['payload'] as Map,
            ),
            'closingLossBalances': losses.map((r) => r['payload']).toList(),
          },
        'residencyPeriods': records
            .where((r) => r['kind'] == 'residency')
            .map((r) => r['payload'])
            .toList(),
        'i1Reviews': records
            .where((r) => r['kind'] == 'i1')
            .map((r) => r['payload'])
            .toList(),
      }
      ..remove('detailSetId')
      ..remove('detailCount')
      ..remove('detailHash');
  }

  Future<Map<String, dynamic>> _hydrateSnapshot(
    String uid,
    Map<String, dynamic> header,
  ) async {
    if (header['schemaVersion'] != 2) return header;
    final payload = await RevisionDetailStore(db: _db).readArchive(uid, header);
    if (header['kind'] == 'finalised') {
      final report = payload['report'];
      if (report is! Map ||
          payload['sourceFingerprint'] != report['sourceFingerprint'] ||
          canonicalTaxFingerprint(header['payloadHeader']) !=
              canonicalTaxFingerprint({
                'sourceFingerprint': payload['sourceFingerprint'],
                'report': {
                  for (final key in [
                    'canFinalise',
                    'workspaceGeneration',
                    'investmentGeneration',
                    'sourceFingerprint',
                  ])
                    key: report[key],
                },
              }) ||
          report['canFinalise'] != true ||
          report['workspaceGeneration'] != header['workspaceGeneration'] ||
          report['investmentGeneration'] != header['investmentGeneration']) {
        throw StateError(
          'Finalised archive header does not match its financial report.',
        );
      }
    } else if (canonicalTaxFingerprint(header['payloadHeader']) !=
        canonicalTaxFingerprint({})) {
      throw StateError('Imported archive header is malformed.');
    }
    return {...header, 'schemaVersion': 1, 'payload': payload}
      ..remove('detailSetId')
      ..remove('detailCount')
      ..remove('detailHash')
      ..remove('payloadHeader');
  }

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
      'workspaceRevisions': await Future.wait(
        revisions.docs.map(
          (version) async => {
            'id': version.id,
            ...await _hydrateWorkspace(uid, version.data()),
          },
        ),
      ),
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
    return Future.wait(
      (await query.get()).docs.map(
        (v) async => {
          'id': v.id,
          ...await _hydrateSnapshot(uid, {...v.data(), 'id': v.id}),
        },
      ),
    );
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
    final frozen = finalSnapshot == null
        ? null
        : jsonDecode(jsonEncode(finalSnapshot)) as Map<String, dynamic>;
    final ref = _year(workspace.userId, workspace.yearStart);
    final metadata = _metadata(workspace.userId);
    final stagedGeneration = await getGeneration(workspace.userId);
    final details = RevisionDetailStore(db: _db);
    final workspaceDetails = await details.stage(
      userId: workspace.userId,
      family: 'workspace',
      subjectId: '${workspace.yearStart}',
      revision: workspace.revision + 1,
      generation: stagedGeneration,
      yearStart: workspace.yearStart,
      records: _workspaceDetails(workspace),
    );
    final archiveDetails = frozen == null
        ? null
        : await details.stageArchive(
            userId: workspace.userId,
            subjectId: '${workspace.revision + 1}',
            revision: workspace.revision + 1,
            generation: stagedGeneration,
            yearStart: workspace.yearStart,
            payload: frozen,
          );
    return _db.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final state = await transaction.get(metadata);
      final investment = await transaction.get(
        _user(workspace.userId).collection('investment_metadata').doc('ledger'),
      );
      final revision = current.data()?['revision'] as int? ?? 0;
      final generation = state.data()?['generation'] as int? ?? 0;
      if (generation != stagedGeneration ||
          revision != workspace.revision ||
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
      await details.verify(transaction, workspaceDetails);
      if (archiveDetails != null) {
        await details.verify(transaction, archiveDetails);
      }
      final logicalData = {
        ...workspace.toMap(),
        'revision': revision + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final data = {
        ...logicalData,
        'schemaVersion': 2,
        ...workspaceDetails.fields,
        'revision': revision + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      data.remove('residencyPeriods');
      data.remove('i1Reviews');
      data.remove('adjudication');
      details.publish(transaction, workspaceDetails);
      if (archiveDetails != null) details.publish(transaction, archiveDetails);
      transaction.set(ref, data);
      transaction.set(ref.collection('revisions').doc('${revision + 1}'), data);
      transaction.set(metadata, {'generation': generation + 1});
      if (frozen != null) {
        transaction.set(ref.collection('snapshots').doc('${revision + 1}'), {
          'schemaVersion': 2,
          ...archiveDetails!.fields,
          'userId': workspace.userId,
          'yearStart': workspace.yearStart,
          'kind': 'finalised',
          'workspaceRevision': revision + 1,
          'workspaceGeneration': generation + 1,
          'investmentGeneration': expectedInvestmentGeneration,
          'createdAt': FieldValue.serverTimestamp(),
          'payloadHeader': {
            'sourceFingerprint': frozen['sourceFingerprint'],
            'report': {
              for (final key in [
                'canFinalise',
                'workspaceGeneration',
                'investmentGeneration',
                'sourceFingerprint',
              ])
                key: frozen['report'][key],
            },
          },
        });
      }
      return TaxWorkspace.fromMap(logicalData);
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
    final raw = (await ref.get()).data();
    final loaded = await getWorkspace(uid, year);
    if (loaded == null ||
        loaded.revision != expectedRevision ||
        loaded.status != 'finalised') {
      throw StateError('Reload the finalised workspace before amending.');
    }
    final generation = await getGeneration(uid);
    final details = RevisionDetailStore(db: _db);
    final staged = raw?['schemaVersion'] != 2
        ? null
        : await details.stage(
            userId: uid,
            family: 'workspace',
            subjectId: '$year',
            revision: expectedRevision + 1,
            generation: generation,
            yearStart: year,
            records: _workspaceDetails(loaded),
          );
    return _db.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final state = await transaction.get(metadata);
      if ((state.data()?['generation'] as int? ?? 0) != generation ||
          current.data()?['status'] != 'finalised' ||
          current.data()?['revision'] != expectedRevision) {
        throw StateError('Reload the finalised workspace before amending.');
      }
      if (staged != null) {
        if (staged.hash != raw?['detailHash']) {
          throw StateError('Amendment must preserve frozen financial details.');
        }
        await details.verify(transaction, staged);
      }
      final data = {
        ...current.data()!,
        if (staged != null) ...{'schemaVersion': 2, ...staged.fields},
        'status': 'draft',
        'amendmentReason': reason.trim(),
        'revision': expectedRevision + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (staged != null) {
        data.remove('residencyPeriods');
        data.remove('i1Reviews');
        data.remove('adjudication');
        details.publish(transaction, staged);
      }
      transaction.set(ref, data);
      transaction.set(
        ref.collection('revisions').doc('${expectedRevision + 1}'),
        data,
      );
      transaction.set(metadata, {
        'generation': (state.data()?['generation'] as int? ?? 0) + 1,
      });
      return loaded.copyWith(
        status: 'draft',
        amendmentReason: reason.trim(),
        revision: expectedRevision + 1,
      );
    });
  }

  Future<String> importHistoricalSnapshot(
    String uid,
    int year,
    Map<String, dynamic> archive,
  ) async {
    final payload = jsonDecode(jsonEncode(archive)) as Map<String, dynamic>;
    final identity = 'imported-${canonicalTaxFingerprint(payload)}';
    final ref = _year(uid, year);
    final snapshot = ref.collection('snapshots').doc(identity);
    final details = RevisionDetailStore(db: _db);
    final staged = await details.stageArchive(
      userId: uid,
      subjectId: identity,
      revision: 0,
      generation: await getGeneration(uid),
      yearStart: year,
      payload: payload,
    );
    await _db.runTransaction((transaction) async {
      final workspace = await transaction.get(ref);
      final existing = await transaction.get(snapshot);
      if (workspace.data()?['status'] != 'draft') {
        throw StateError('Historical imports require a draft workspace.');
      }
      if (!existing.exists) {
        await details.verify(transaction, staged);
        details.publish(transaction, staged);
        transaction.set(snapshot, {
          'schemaVersion': 2,
          ...staged.fields,
          'kind': 'imported',
          'userId': uid,
          'yearStart': year,
          'createdAt': FieldValue.serverTimestamp(),
          'payloadHeader': {},
        });
      }
    });
    return identity;
  }
}

List<Map<String, dynamic>> _workspaceDetails(TaxWorkspace workspace) => [
  for (final p in workspace.residencyPeriods)
    {'kind': 'residency', 'payload': p.toMap()},
  for (final i in workspace.i1Reviews) {'kind': 'i1', 'payload': i.toMap()},
  if (workspace.adjudication != null) ...[
    {
      'kind': 'adjudication',
      'payload': workspace.adjudication!.toMap()..remove('closingLossBalances'),
    },
    for (final balance in workspace.adjudication!.closingLossBalances)
      {'kind': 'adjudicationLoss', 'payload': balance.toMap()},
  ],
];
