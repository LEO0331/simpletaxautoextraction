import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/source_fingerprint.dart';

class RevisionDetailSet {
  final String id, userId, family, hash;
  final int count, revision, generation;
  const RevisionDetailSet({
    required this.id,
    required this.userId,
    required this.family,
    required this.hash,
    required this.count,
    required this.revision,
    required this.generation,
  });
  Map<String, dynamic> get fields => Map.unmodifiable({
    'detailSetId': id,
    'detailCount': count,
    'detailHash': hash,
  });
}

/// Typed records are staged in small rule-budget-safe batches, then linked by
/// an atomic parent publication. Partial/unpublished/mismatched sets never read.
class RevisionDetailStore {
  final FirebaseFirestore _db;
  RevisionDetailStore({required FirebaseFirestore db}) : _db = db;
  DocumentReference<Map<String, dynamic>> _ref(String uid, String id) =>
      _db.collection('users').doc(uid).collection('revision_details').doc(id);
  static const _kinds = {
    'allocation': {'allocation'},
    'fund': {'fundAdjustment', 'fundDrp'},
    'workspace': {'residency', 'i1', 'adjudication', 'adjudicationLoss'},
    'archive': {'archiveChunk'},
  };

  Future<RevisionDetailSet> stage({
    required String userId,
    required String family,
    required String subjectId,
    required int revision,
    required int generation,
    int yearStart = 0,
    String ticker = '',
    String accountNumber = '',
    int saleRevision = 0,
    bool reviewed = false,
    required List<Map<String, dynamic>> records,
  }) async {
    if (userId.trim().isEmpty ||
        !_kinds.containsKey(family) ||
        subjectId.isEmpty ||
        subjectId.contains('/') ||
        revision < 0 ||
        generation < 0) {
      throw ArgumentError('Invalid detail-set context.');
    }
    final normalized = <Map<String, dynamic>>[];
    try {
      for (final raw in records) {
        if (raw.keys.length != 2 ||
            !_kinds[family]!.contains(raw['kind']) ||
            raw['payload'] is! Map) {
          throw const FormatException();
        }
        normalized.add(
          Map<String, dynamic>.from(jsonDecode(jsonEncode(raw)) as Map),
        );
      }
    } catch (_) {
      throw StateError('Unsupported detail record.');
    }
    final hash = _fingerprint(normalized);
    final context = <String, dynamic>{
      'schemaVersion': 1,
      'userId': userId,
      'family': family,
      'subjectId': subjectId,
      'yearStart': yearStart,
      'revision': revision,
      'generation': generation,
      'ticker': ticker,
      'accountNumber': accountNumber,
      'saleRevision': saleRevision,
      'reviewed': reviewed,
      'count': normalized.length,
      'hash': hash,
    };
    final id = _fingerprint(context);
    final descriptor = RevisionDetailSet(
      id: id,
      userId: userId,
      family: family,
      hash: hash,
      count: normalized.length,
      revision: revision,
      generation: generation,
    );
    final ref = _ref(userId, id);
    final existing = await ref.get();
    if (!existing.exists) {
      await ref.set({
        ...context,
        'state': 'staging',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else if (context.entries.any((e) => existing.data()?[e.key] != e.value)) {
      throw StateError('Detail-set identity conflicts.');
    } else if (existing.data()?['state'] == 'published') {
      await read(userId, descriptor.fields, family: family);
      return descriptor;
    }
    // Four is a batch size, not a feature/record limit. Distinct referenced
    // acquisitions stay below the 20-document security-rule access budget.
    for (var start = 0; start < normalized.length; start += 4) {
      final batch = _db.batch();
      var changed = false;
      for (
        var index = start;
        index < min(start + 4, normalized.length);
        index++
      ) {
        final record = {...normalized[index], 'index': index};
        final child = ref.collection('records').doc('$index');
        final saved = await child.get();
        if (saved.exists) {
          if (_fingerprint(saved.data()) != _fingerprint(record)) {
            throw StateError('Staged detail record conflicts.');
          }
        } else {
          batch.set(child, record);
          changed = true;
        }
      }
      if (changed) await batch.commit();
    }
    return descriptor;
  }

  Future<void> verify(Transaction transaction, RevisionDetailSet set) async {
    final snapshot = await transaction.get(_ref(set.userId, set.id));
    final data = snapshot.data();
    if (data == null ||
        data['state'] != 'staging' ||
        data['userId'] != set.userId ||
        data['family'] != set.family ||
        data['count'] != set.count ||
        data['hash'] != set.hash ||
        data['revision'] != set.revision ||
        data['generation'] != set.generation) {
      throw StateError('Detail publication changed. Reload before saving.');
    }
  }

  /// Call only after every transaction read/verify is complete.
  void publish(Transaction transaction, RevisionDetailSet set) =>
      transaction.update(_ref(set.userId, set.id), {'state': 'published'});

  Future<List<Map<String, dynamic>>> read(
    String userId,
    Map<String, dynamic> header, {
    String? family,
    String? subjectId,
  }) async {
    final id = header['detailSetId'];
    final count = header['detailCount'];
    final hash = header['detailHash'];
    if (id is! String || count is! int || count < 0 || hash is! String) {
      throw StateError('Missing detail manifest. Review the source.');
    }
    final ref = _ref(userId, id);
    final manifest = (await ref.get()).data();
    if (manifest == null ||
        manifest['state'] != 'published' ||
        manifest['userId'] != userId ||
        (family != null && manifest['family'] != family) ||
        !_kinds.containsKey(manifest['family']) ||
        (subjectId != null && manifest['subjectId'] != subjectId) ||
        (header.containsKey('revision') &&
            manifest['revision'] != header['revision']) ||
        (family == 'archive' &&
            header.containsKey('workspaceRevision') &&
            manifest['revision'] != header['workspaceRevision']) ||
        (header.containsKey('yearStart') &&
            manifest['yearStart'] != header['yearStart']) ||
        (header.containsKey('ticker') &&
            manifest['ticker'] != header['ticker']) ||
        (header.containsKey('accountNumber') &&
            manifest['accountNumber'] != header['accountNumber']) ||
        (family == 'allocation' &&
            header.containsKey('sellTransactionId') &&
            manifest['subjectId'] != header['sellTransactionId']) ||
        (family == 'allocation' &&
            header.containsKey('saleRevision') &&
            manifest['saleRevision'] != header['saleRevision']) ||
        manifest['count'] != count ||
        manifest['hash'] != hash) {
      throw StateError(
        'Unpublished or changed detail manifest. Review the source.',
      );
    }
    final documents = await ref.collection('records').orderBy('index').get();
    if (documents.docs.length != count) {
      throw StateError('Incomplete detail set. Review the source.');
    }
    final result = <Map<String, dynamic>>[];
    for (var index = 0; index < documents.docs.length; index++) {
      final record = documents.docs[index].data();
      if (record['index'] != index ||
          documents.docs[index].id != '$index' ||
          !_kinds[manifest['family']]!.contains(record['kind']) ||
          record['payload'] is! Map ||
          record.keys.toSet().difference({
            'index',
            'kind',
            'payload',
          }).isNotEmpty) {
        throw StateError('Malformed detail sequence. Review the source.');
      }
      result.add({
        'kind': record['kind'],
        'payload': Map<String, dynamic>.from(record['payload'] as Map),
      });
    }
    if (_fingerprint(result) != hash) {
      throw StateError('Detail fingerprint mismatch. Review the source.');
    }
    return result;
  }

  Future<RevisionDetailSet> stageArchive({
    required String userId,
    required String subjectId,
    required int revision,
    required int generation,
    required int yearStart,
    required Map<String, dynamic> payload,
  }) async {
    late List<int> bytes;
    try {
      bytes = utf8.encode(jsonEncode(payload));
    } catch (_) {
      throw StateError('Archive must contain serializable structured facts.');
    }
    final records = <Map<String, dynamic>>[];
    const chunkBytes = 180000;
    for (var offset = 0; offset < bytes.length; offset += chunkBytes) {
      records.add({
        'kind': 'archiveChunk',
        'payload': {
          'data': base64Encode(
            bytes.sublist(offset, min(offset + chunkBytes, bytes.length)),
          ),
        },
      });
    }
    return stage(
      userId: userId,
      family: 'archive',
      subjectId: subjectId,
      revision: revision,
      generation: generation,
      yearStart: yearStart,
      records: records,
    );
  }

  Future<Map<String, dynamic>> readArchive(
    String userId,
    Map<String, dynamic> header,
  ) async {
    try {
      final records = await read(
        userId,
        header,
        family: 'archive',
        subjectId: header['id'] as String?,
      );
      final bytes = <int>[];
      for (final record in records) {
        bytes.addAll(
          base64Decode((record['payload'] as Map)['data'] as String),
        );
      }
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
    } catch (_) {
      throw StateError(
        'Archive is incomplete or unreadable. Review the source.',
      );
    }
  }
}

String _fingerprint(dynamic value) =>
    SourceFingerprint.text(jsonEncode(_canonical(value)));
dynamic _canonical(dynamic value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}
