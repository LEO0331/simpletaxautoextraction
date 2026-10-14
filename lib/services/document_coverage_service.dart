import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/document_coverage.dart';
import '../utils/source_fingerprint.dart';

class DocumentCoverageService {
  final FirebaseFirestore _db;
  DocumentCoverageService({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;
  Future<List<DocumentCoverage>> getCoverage(String uid, int year) async =>
      (await _db
              .collection('users')
              .doc(uid)
              .collection('document_coverage')
              .where('taxYearStart', isEqualTo: year)
              .get())
          .docs
          .map((d) => DocumentCoverage.fromMap(d.data(), id: d.id))
          .where((r) => !r.isVoided)
          .toList();
  Future<DocumentCoverage> save(
    DocumentCoverage record, {
    required int expectedRevision,
  }) async {
    final errors = record.validation();
    if (errors.isNotEmpty) throw FormatException(errors.join(' '));
    final user = _db.collection('users').doc(record.userId);
    final id =
        record.id ??
        SourceFingerprint.text(
          jsonEncode([
            record.taxYearStart,
            record.account,
            record.ticker,
            record.family,
            record.sourceHash,
            record.firstPage,
            record.lastPage,
            record.linkedRecordId,
            record.evidenceReference,
          ]),
        );
    final ref = user.collection('document_coverage').doc(id),
        meta = user.collection('tax_workspace_metadata').doc('current');
    return _db.runTransaction((tx) async {
      final old = await tx.get(ref), generation = await tx.get(meta);
      if ((old.data()?['revision'] ?? 0) != expectedRevision ||
          record.revision != expectedRevision) {
        throw StateError('Evidence changed. Reload before saving.');
      }
      final map = {
        ...record.toMap(),
        'revision': expectedRevision + 1,
        'createdAt': old.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      tx.set(ref, map);
      tx.set(ref.collection('revisions').doc('${expectedRevision + 1}'), map);
      tx.set(meta, {
        'generation': ((generation.data()?['generation'] as int?) ?? 0) + 1,
      });
      return DocumentCoverage.fromMap(map, id: id);
    });
  }
}
