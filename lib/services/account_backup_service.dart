import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/investment_transaction.dart';
import '../models/managed_fund_statement.dart';
import '../models/tax_record.dart';
import '../models/tax_workspace.dart';
import 'firestore_service.dart';
import 'tax_workspace_service.dart';

/// Complete owner-bound recovery. Historical records are passive evidence;
/// active facts are restored as drafts through the ordinary validated writers.
/// PDF bytes, authentication data and the users/{uid} profile are excluded.
class AccountBackupService {
  final FirebaseFirestore db;
  late final FirestoreService investments = FirestoreService(db: db);
  late final TaxWorkspaceService workspaces = TaxWorkspaceService(db: db);
  AccountBackupService({FirebaseFirestore? db})
    : db = db ?? FirebaseFirestore.instance;

  static const collections = [
    'tax_records',
    'properties',
    'settings',
    'investment_transactions',
    'investment_allocations',
    'investment_sources',
    'investment_metadata',
    'managed_fund_statements',
    'investment_calculation_snapshots',
    'tax_years',
    'tax_workspace_metadata',
    'revision_details',
    'account_restores',
  ];
  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      db.collection('users').doc(uid);

  Future<String> exportAccount(String uid) async {
    _owner(uid);
    final generations = await _generations(uid);
    final records = <Map<String, dynamic>>[];
    for (final collection in collections) {
      for (final doc in (await _user(uid).collection(collection).get()).docs) {
        await _collect(doc, '$collection/${doc.id}', records);
      }
    }
    final logical = <String, dynamic>{
      'transactions': (await investments.getInvestmentTransactionsOnce(
        uid,
        includeVoided: true,
      )).map((v) => {'id': v.id, 'data': _encode(v.toMap())}).toList(),
      'funds': (await investments.getManagedFundStatementsOnce(
        uid,
        includeVoided: true,
      )).map((v) => {'id': v.id, 'data': _encode(v.toMap())}).toList(),
      'workspaces': <Map<String, dynamic>>[],
    };
    for (final workspace in await workspaces.getWorkspaces(uid)) {
      (logical['workspaces'] as List).add({
        'data': workspace.toMap(),
        'items': (await workspaces.getItems(
          uid,
          workspace.yearStart,
        )).map((v) => {'id': v.id, 'data': v.toMap()}).toList(),
      });
    }
    // Properties/parser mappings do not advance either financial generation.
    for (final collection in ['properties', 'settings']) {
      final before = records
          .where((r) => (r['path'] as String).startsWith('$collection/'))
          .toList();
      final after = (await _user(uid).collection(collection).get()).docs
          .map(
            (v) => {'path': '$collection/${v.id}', 'data': _encode(v.data())},
          )
          .toList();
      before.sort(
        (a, b) => (a['path'] as String).compareTo(b['path'] as String),
      );
      after.sort(
        (a, b) => (a['path'] as String).compareTo(b['path'] as String),
      );
      if (canonicalTaxFingerprint(before) != canonicalTaxFingerprint(after)) {
        throw StateError(
          'Property or parser settings changed during backup. Retry.',
        );
      }
    }
    if (canonicalTaxFingerprint(generations) !=
        canonicalTaxFingerprint(await _generations(uid))) {
      throw StateError('Sources changed during backup. Reload and retry.');
    }
    records.sort(
      (a, b) => (a['path'] as String).compareTo(b['path'] as String),
    );
    final data = {
      'format': 'au-tax-account-backup',
      'version': 1,
      'userId': uid,
      'records': records,
      'logical': logical,
    };
    validate(data, uid);
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<List<int>> _generations(String uid) async => [
    await investments.getInvestmentLedgerGeneration(uid),
    await workspaces.getGeneration(uid),
  ];

  Future<void> _collect(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String path,
    List<Map<String, dynamic>> records,
  ) async {
    records.add({'path': path, 'data': _encode(doc.data())});
    final parts = path.split('/');
    final children = <String>[
      if (parts.length == 2 &&
          [
            'investment_transactions',
            'investment_allocations',
            'managed_fund_statements',
            'tax_years',
          ].contains(parts.first))
        'revisions',
      if (parts.length == 2 && parts.first == 'tax_years') ...[
        'items',
        'snapshots',
      ],
      if (parts.length == 4 && parts[2] == 'items') 'revisions',
      if (parts.length == 2 && parts.first == 'revision_details') 'records',
      if (parts.length == 2 && parts.first == 'account_restores') 'records',
    ];
    for (final child in children) {
      for (final nested in (await doc.reference.collection(child).get()).docs) {
        await _collect(nested, '$path/$child/${nested.id}', records);
      }
    }
  }

  /// Entire payload validation precedes all reads/writes in restoreAccount.
  static AccountRestorePreview validate(
    Map<String, dynamic> backup,
    String uid,
  ) {
    try {
      _owner(uid);
      if (backup.keys.toSet().difference({
            'format',
            'version',
            'userId',
            'records',
            'logical',
          }).isNotEmpty ||
          backup['format'] != 'au-tax-account-backup' ||
          backup['version'] != 1 ||
          backup['userId'] != uid) {
        throw const FormatException('Unsupported or wrong-owner backup.');
      }
      _walk(backup, uid);
      final records = (backup['records'] as List).cast<Map>();
      final paths = <String>{};
      final byPath = <String, Map<String, dynamic>>{};
      for (final record in records) {
        if (record.keys.toSet().difference({'path', 'data'}).isNotEmpty) {
          throw const FormatException('Unknown backup record field.');
        }
        final path = record['path'] as String;
        if (!_validPath(path) || !paths.add(path)) {
          throw const FormatException('Invalid or duplicate record path.');
        }
        final data = Map<String, dynamic>.from(record['data'] as Map);
        if (utf8.encode(jsonEncode(data)).length > 700000) {
          throw const FormatException('Backup record exceeds recovery size.');
        }
        _decode(data); // Validate every encoded type before any write.
        byPath[path] = data;
      }
      for (final path in paths) {
        final parts = path.split('/');
        if (parts.length > 2 &&
            !paths.contains(parts.take(parts.length - 2).join('/'))) {
          throw const FormatException('Missing historical parent record.');
        }
      }
      for (final entry in byPath.entries) {
        final header = entry.value;
        if (header.containsKey('detailSetId')) {
          _details(header, byPath);
        }
        if (entry.key.startsWith('properties/')) {
          if (header.keys.toSet().difference({
                'name',
                'createdAt',
                'updatedAt',
              }).isNotEmpty ||
              header['name'] is! String ||
              (header['name'] as String).trim().isEmpty ||
              (header['name'] as String).length > 120) {
            throw const FormatException('Invalid property.');
          }
        }
        if (entry.key.startsWith('settings/')) {
          if (entry.key != 'settings/mappings' ||
              header.keys.toSet().difference({
                'income',
                'expense',
                'updatedAt',
              }).isNotEmpty) {
            throw const FormatException('Invalid parser settings.');
          }
          for (final kind in ['income', 'expense']) {
            final mappings = Map<String, String>.from(header[kind] as Map);
            final categories = kind == 'income'
                ? TaxRecord.incomeCategoryOptions
                : TaxRecord.expenseCategoryOptions;
            if (mappings.entries.any(
              (e) => e.key.trim().isEmpty || !categories.contains(e.value),
            )) {
              throw const FormatException('Invalid parser mapping.');
            }
          }
        }
      }
      final logical = Map<String, dynamic>.from(backup['logical'] as Map);
      if (logical.keys.toSet().difference({
        'transactions',
        'funds',
        'workspaces',
      }).isNotEmpty) {
        throw const FormatException('Unknown logical backup section.');
      }
      final transactionIds = <String>{};
      final transactionSources = <String>{};
      for (final raw in logical['transactions'] as List) {
        final id = raw['id'] as String;
        if (!_validId(id) ||
            !transactionIds.add(id) ||
            !byPath.containsKey('investment_transactions/$id')) {
          throw const FormatException(
            'Transaction source is missing or duplicated.',
          );
        }
        final fact = InvestmentTransaction.fromMap(
          Map<String, dynamic>.from(_decode(raw['data']) as Map),
          id,
        );
        final archived = InvestmentTransaction.fromMap(
          Map<String, dynamic>.from(
            _decode(byPath['investment_transactions/$id']) as Map,
          ),
          id,
        );
        if (canonicalTaxFingerprint(_encode(fact.toMap())) !=
            canonicalTaxFingerprint(_encode(archived.toMap()))) {
          throw const FormatException(
            'Logical transaction does not match evidence.',
          );
        }
        if (fact.userId != uid ||
            !fact.units.isFinite ||
            !fact.consideration.isFinite ||
            !fact.brokerage.isFinite ||
            !fact.totalCost.isFinite ||
            !fact.averagePrice.isFinite ||
            fact.units <= 0 ||
            fact.averagePrice <= 0 ||
            fact.consideration < 0 ||
            fact.brokerage < 0 ||
            fact.totalCost <= 0 ||
            (fact.gst != null && (!fact.gst!.isFinite || fact.gst! < 0)) ||
            fact.ticker.isEmpty ||
            fact.ticker.length > 16 ||
            fact.securityName.isEmpty ||
            fact.securityName.length > 180 ||
            fact.sourceParser.length > 120 ||
            fact.parserVersion.length > 24 ||
            fact.notes.length > 2000) {
          throw const FormatException('Invalid transaction facts.');
        }
        final confirmation = fact.confirmationNumber?.trim() ?? '';
        final source = canonicalTaxFingerprint([
          fact.sourceParser.trim().isEmpty
              ? 'commsec trade confirmation parser'
              : fact.sourceParser.trim().toLowerCase(),
          fact.accountNumber?.trim() ?? '',
          if (confirmation.isNotEmpty)
            ['confirmation', confirmation]
          else if (fact.sourceHash?.isNotEmpty ?? false)
            ['source', fact.sourceHash]
          else
            [
              'facts',
              fact.ticker.trim().toUpperCase(),
              fact.transactionType.value,
              fact.toMap()['tradeDateIso'],
              fact.unitsExact ?? fact.units.toString(),
              fact.totalCostExact ?? fact.totalCost.toString(),
            ],
        ]);
        if (!transactionSources.add(source)) {
          throw const FormatException(
            'Duplicate transaction sources require review before recovery.',
          );
        }
      }
      final funds = <String>{};
      for (final raw in logical['funds'] as List) {
        final id = raw['id'] as String;
        final fact = ManagedFundStatement.fromMap(
          Map<String, dynamic>.from(raw['data'] as Map),
          id: id,
        );
        final archived = ManagedFundStatement.fromMap(
          _hydrate(byPath['managed_fund_statements/$id']!, byPath, 'fund'),
          id: id,
        );
        if (canonicalTaxFingerprint(fact.toMap()) !=
            canonicalTaxFingerprint(archived.toMap())) {
          throw const FormatException(
            'Logical statement does not match evidence.',
          );
        }
        if (!_validId(id) ||
            !funds.add(id) ||
            fact.userId != uid ||
            !byPath.containsKey('managed_fund_statements/$id')) {
          throw const FormatException('Invalid fund source identity.');
        }
        if (id !=
            canonicalTaxFingerprint([
              fact.accountNumber.trim(),
              fact.ticker.trim().toUpperCase(),
              fact.yearStart,
            ])) {
          throw const FormatException(
            'Fund identity differs from its source fields.',
          );
        }
        if (fact.components.keys.any(
              (key) => !ManagedFundStatement.allComponentKeys.contains(key),
            ) ||
            fact.components.values.any((value) => !workspaceMoney(value)) ||
            fact.adjustments.any(
              (a) => !workspaceMoney(a.amount, signed: true),
            )) {
          throw const FormatException('Invalid statement monetary fields.');
        }
        for (final adjustment in fact.adjustments) {
          workspaceDate(adjustment.date);
        }
        for (final ref in [
          ...fact.adjustments.map((v) => v.parcelId),
          ...fact.adjustments.map((v) => v.beforeSaleId).whereType<String>(),
          ...fact.drpLinks.map((v) => v.buyTransactionId),
        ]) {
          if (!transactionIds.contains(ref)) {
            throw const FormatException('Missing fund transaction reference.');
          }
        }
      }
      for (final entry in byPath.entries.where(
        (e) =>
            e.key.startsWith('investment_allocations/') &&
            e.key.split('/').length == 2,
      )) {
        final data = entry.value;
        if (!transactionIds.contains(data['sellTransactionId'])) {
          throw const FormatException('Missing allocation sale reference.');
        }
        // Schema 2 selections live in exported detail records; schema 1 inline.
        for (final selection
            in data['schemaVersion'] == 2
                ? _details(data, byPath).map((v) => v['payload'])
                : data['selections'] as List? ?? const []) {
          if (!transactionIds.contains(selection['buyTransactionId'])) {
            throw const FormatException('Missing allocation parcel reference.');
          }
        }
      }
      final years = <int>{};
      var items = 0;
      for (final raw in logical['workspaces'] as List) {
        final workspace = TaxWorkspace.fromMap(
          Map<String, dynamic>.from(raw['data'] as Map),
        );
        final archived = TaxWorkspace.fromMap(
          _hydrate(
            byPath['tax_years/${workspace.yearStart}']!,
            byPath,
            'workspace',
          ),
        );
        if (canonicalTaxFingerprint(workspace.toMap()) !=
            canonicalTaxFingerprint(archived.toMap())) {
          throw const FormatException(
            'Logical workspace does not match evidence.',
          );
        }
        if (workspace.userId != uid ||
            !years.add(workspace.yearStart) ||
            !byPath.containsKey('tax_years/${workspace.yearStart}') ||
            workspace.validation().isNotEmpty) {
          throw const FormatException('Invalid workspace.');
        }
        final itemIds = <String>{};
        for (final value in raw['items'] as List) {
          final id = value['id'] as String;
          final item = TaxWorkspaceItem.fromMap(
            Map<String, dynamic>.from(value['data'] as Map),
            id: id,
          );
          final archived = TaxWorkspaceItem.fromMap(
            Map<String, dynamic>.from(
              byPath['tax_years/${workspace.yearStart}/items/$id']!,
            ),
            id: id,
          );
          if (canonicalTaxFingerprint(item.toMap()) !=
              canonicalTaxFingerprint(archived.toMap())) {
            throw const FormatException(
              'Logical item does not match evidence.',
            );
          }
          if (!_validId(id) ||
              !itemIds.add(id) ||
              item.userId != uid ||
              item.yearStart != workspace.yearStart ||
              item.validation().isNotEmpty ||
              !byPath.containsKey(
                'tax_years/${workspace.yearStart}/items/$id',
              ) ||
              (item.rentalRecordId.isNotEmpty &&
                  !byPath.containsKey('tax_records/${item.rentalRecordId}'))) {
            throw const FormatException('Invalid or orphaned workspace item.');
          }
          if (id !=
              canonicalTaxFingerprint([
                item.category,
                item.sourceReference.trim(),
              ])) {
            throw const FormatException(
              'Item identity differs from its source fields.',
            );
          }
          items++;
        }
      }
      // Root source documents must all have logical counterparts.
      if (byPath.keys
                  .where(
                    (p) =>
                        p.split('/').length == 2 &&
                        p.startsWith('investment_transactions/'),
                  )
                  .length !=
              transactionIds.length ||
          byPath.keys
                  .where(
                    (p) =>
                        p.split('/').length == 2 &&
                        p.startsWith('managed_fund_statements/'),
                  )
                  .length !=
              funds.length ||
          byPath.keys
                  .where(
                    (p) =>
                        p.split('/').length == 2 && p.startsWith('tax_years/'),
                  )
                  .length !=
              years.length) {
        throw const FormatException('Incomplete logical source inventory.');
      }
      for (final entry in byPath.entries.where(
        (e) => e.key.startsWith('tax_records/'),
      )) {
        final fact = TaxRecord.fromMap(
          Map<String, dynamic>.from(_decode(entry.value) as Map),
          entry.key.split('/').last,
        );
        if (fact.userId != uid ||
            !RegExp(r'^\d{4}-\d{4}$').hasMatch(fact.financialYear) ||
            [
              ...fact.income.values,
              ...fact.expenses.values,
            ].any((v) => !v.isFinite || v < 0)) {
          throw const FormatException('Invalid rental source.');
        }
      }
      return AccountRestorePreview(
        canonicalTaxFingerprint(backup),
        records.length,
        transactionIds.length,
        funds.length,
        years.length,
        items,
      );
    } catch (_) {
      throw const FormatException(
        'Invalid, incomplete, unsupported or wrong-owner account backup.',
      );
    }
  }

  /// Evidence is immutable and resumable by content hash. Allocations and tax
  /// snapshots stay historical until the user reviews fresh source facts.
  Future<AccountRestorePreview> restoreAccount(String uid, String json) async {
    if (utf8.encode(json).length > 100000000) {
      throw const FormatException('Account backup exceeds 100 MB.');
    }
    final backup = Map<String, dynamic>.from(jsonDecode(json) as Map);
    final preview = validate(backup, uid);
    final operation = _user(
      uid,
    ).collection('account_restores').doc(preview.hash);
    final existingOperation = await operation.get();
    if (existingOperation.exists &&
        (existingOperation.data()?['backupHash'] != preview.hash ||
            existingOperation.data()?['recordCount'] != preview.recordCount ||
            existingOperation.data()?['userId'] != uid ||
            existingOperation.data()?['schemaVersion'] != 1)) {
      throw StateError('Recovery operation does not match this backup.');
    }
    // Never overwrite a live dataset, including on a failed-operation retry.
    await _assertDestination(uid, backup, existingOperation.exists);
    await db.runTransaction((tx) async {
      final current = await tx.get(operation);
      if (current.exists &&
          (current.data()?['backupHash'] != preview.hash ||
              current.data()?['recordCount'] != preview.recordCount ||
              current.data()?['userId'] != uid)) {
        throw StateError('Recovery operation changed.');
      }
      if (!current.exists) {
        tx.set(operation, {
          'schemaVersion': 1,
          'userId': uid,
          'backupHash': preview.hash,
          'recordCount': preview.recordCount,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
    for (final raw in backup['records'] as List) {
      final path = raw['path'] as String;
      final payload = Map<String, dynamic>.from(raw['data'] as Map);
      final record = operation
          .collection('records')
          .doc(canonicalTaxFingerprint(path));
      final value = {
        'schemaVersion': 1,
        'userId': uid,
        'path': path,
        'payload': payload,
        'recordHash': canonicalTaxFingerprint(payload),
      };
      await db.runTransaction((tx) async {
        final old = await tx.get(record);
        if (old.exists &&
            canonicalTaxFingerprint(old.data()) !=
                canonicalTaxFingerprint(value)) {
          throw StateError('Recovery evidence conflicts with this backup.');
        }
        if (!old.exists) tx.set(record, value);
      });
    }
    await _assertDestination(uid, backup, true);
    await _activate(uid, backup);
    return preview;
  }

  Future<void> _assertDestination(
    String uid,
    Map<String, dynamic> backup,
    bool resume,
  ) async {
    if (!resume) {
      for (final collection in ['investment_sources', 'revision_details']) {
        if ((await _user(
          uid,
        ).collection(collection).limit(1).get()).docs.isNotEmpty) {
          throw StateError('Full recovery requires an empty account dataset.');
        }
      }
    }
    final expected = _drafts(backup);
    for (final collection in collections.where(
      (c) => ![
        'investment_metadata',
        'tax_workspace_metadata',
        'revision_details',
        'investment_sources',
        'account_restores',
      ].contains(c),
    )) {
      for (final doc in (await _user(uid).collection(collection).get()).docs) {
        final wanted = expected['$collection/${doc.id}'];
        if (!resume || wanted == null) {
          throw StateError(
            'Full recovery requires an empty account dataset. Export current data first.',
          );
        }
        var actual = doc.data();
        if (collection == 'managed_fund_statements') {
          actual = (await investments.getManagedFundStatementsOnce(
            uid,
            includeVoided: true,
          )).firstWhere((v) => v.id == doc.id).toMap();
        } else if (collection == 'tax_years') {
          actual = (await workspaces.getWorkspace(
            uid,
            int.parse(doc.id),
          ))!.toMap();
        }
        if (canonicalTaxFingerprint(_financial(actual)) !=
            canonicalTaxFingerprint(_financial(wanted))) {
          throw StateError(
            'Recovered data has since changed. Recovery will not overwrite it.',
          );
        }
        if (collection == 'tax_years') {
          for (final item in await workspaces.getItems(
            uid,
            int.parse(doc.id),
          )) {
            final wantedItem = expected['tax_years/${doc.id}/items/${item.id}'];
            if (wantedItem == null ||
                canonicalTaxFingerprint(_financial(item.toMap())) !=
                    canonicalTaxFingerprint(_financial(wantedItem))) {
              throw StateError(
                'Workspace sources have changed since recovery.',
              );
            }
          }
        }
      }
    }
  }

  static Map<String, Map<String, dynamic>> _drafts(
    Map<String, dynamic> backup,
  ) {
    final result = <String, Map<String, dynamic>>{};
    for (final raw in backup['records'] as List) {
      final path = raw['path'] as String;
      if (path.split('/').length != 2) continue;
      final data = Map<String, dynamic>.from(_decode(raw['data']) as Map);
      if (path.startsWith('tax_records/')) {
        result[path] = TaxRecord.fromMap(
          data,
          path.split('/').last,
        ).copyWith(isLocked: false).toMap();
      } else if (path.startsWith('properties/') ||
          path.startsWith('settings/')) {
        result[path] = data;
      }
    }
    final logical = backup['logical'] as Map;
    for (final raw in logical['transactions'] as List) {
      result['investment_transactions/${raw['id']}'] = {
        ...Map<String, dynamic>.from(_decode(raw['data']) as Map),
        'isReviewed': false,
        'isLocked': false,
        'revision': 0,
      };
    }
    for (final raw in logical['funds'] as List) {
      result['managed_fund_statements/${raw['id']}'] = {
        ...Map<String, dynamic>.from(raw['data'] as Map),
        'isReviewed': false,
        'revision': 0,
      };
    }
    for (final raw in logical['workspaces'] as List) {
      final source = TaxWorkspace.fromMap(
        Map<String, dynamic>.from(raw['data'] as Map),
      );
      result['tax_years/${source.yearStart}'] = source
          .copyWith(
            revision: 0,
            status: 'draft',
            cgtSnapshotId: '',
            amendmentReason: '',
            sectionStates: {
              for (final key in source.sectionStates.keys) key: 'needsReview',
            },
            residencyPeriods: source.residencyPeriods
                .map(
                  (v) => ResidencyPeriod.fromMap({
                    ...v.toMap(),
                    'reviewed': false,
                  }),
                )
                .toList(),
            i1Reviews: const [],
          )
          .toMap();
      for (final rawItem in raw['items'] as List) {
        result['tax_years/${source.yearStart}/items/${rawItem['id']}'] = {
          ...Map<String, dynamic>.from(rawItem['data'] as Map),
          'isReviewed': false,
          'revision': 0,
        };
      }
    }
    return result;
  }

  Future<void> _activate(String uid, Map<String, dynamic> backup) async {
    final drafts = _drafts(backup);
    for (final entry in drafts.entries) {
      final parts = entry.key.split('/');
      final ref = _user(uid).collection(parts[0]).doc(parts[1]);
      // Retry skips already activated identical facts checked above.
      final target = parts.length == 4
          ? ref.collection(parts[2]).doc(parts[3])
          : ref;
      final current = await target.get();
      if (current.exists) {
        await _assertDestination(uid, backup, true);
        continue;
      }
      switch (parts[0]) {
        case 'properties':
        case 'settings':
          await db.runTransaction((tx) async {
            final existing = await tx.get(target);
            if (existing.exists) {
              if (canonicalTaxFingerprint(_financial(existing.data()!)) !=
                  canonicalTaxFingerprint(_financial(entry.value))) {
                throw StateError(
                  'Existing settings or property changed during recovery.',
                );
              }
            } else {
              tx.set(target, entry.value);
            }
          });
        case 'tax_records':
          await investments.restoreRentalRecord(
            TaxRecord.fromMap(entry.value, parts[1]),
          );
        case 'investment_transactions':
          final data = InvestmentTransaction.fromMap(entry.value, parts[1]);
          await investments.saveInvestmentTransaction(
            InvestmentTransaction.fromMap(data.toMap(), ''),
            creationId: parts[1],
          );
        case 'managed_fund_statements':
          await investments.saveManagedFundStatement(
            ManagedFundStatement.fromMap(entry.value, id: parts[1]),
          );
        case 'tax_years':
          if (parts.length == 2) {
            await workspaces.saveWorkspace(TaxWorkspace.fromMap(entry.value));
          } else {
            await workspaces.saveItem(
              TaxWorkspaceItem.fromMap(entry.value, id: parts[3]),
            );
          }
      }
    }
  }

  Future<List<Map<String, dynamic>>> getRecoveryEvidence(
    String uid,
    String hash,
  ) async =>
      (await _user(uid)
              .collection('account_restores')
              .doc(hash)
              .collection('records')
              .get())
          .docs
          .map((v) => v.data())
          .toList();
  Future<List<String>> getRecoveryIds(String uid) async => (await _user(
    uid,
  ).collection('account_restores').get()).docs.map((v) => v.id).toList();

  static Map<String, dynamic> _financial(Map<String, dynamic> map) =>
      Map<String, dynamic>.from(
        _encode(
              {...map}
                ..remove('createdAt')
                ..remove('updatedAt')
                ..remove('revision')
                ..remove('sourceIdentity'),
            )
            as Map,
      );

  static List<Map<String, dynamic>> _details(
    Map<String, dynamic> header,
    Map<String, Map<String, dynamic>> records,
  ) {
    final id = header['detailSetId'];
    final count = header['detailCount'];
    final manifest = records['revision_details/$id'];
    if (id is! String ||
        count is! int ||
        count < 0 ||
        manifest == null ||
        manifest['state'] != 'published' ||
        manifest['count'] != count ||
        manifest['hash'] != header['detailHash']) {
      throw const FormatException('Missing or unpublished detail set.');
    }
    final result = <Map<String, dynamic>>[];
    for (var index = 0; index < count; index++) {
      final value = records['revision_details/$id/records/$index'];
      if (value == null ||
          value['index'] != index ||
          value['kind'] is! String ||
          value['payload'] is! Map) {
        throw const FormatException('Incomplete detail set.');
      }
      result.add({'kind': value['kind'], 'payload': value['payload']});
    }
    if (canonicalTaxFingerprint(result) != header['detailHash']) {
      throw const FormatException('Changed detail set.');
    }
    return result;
  }

  static Map<String, dynamic> _hydrate(
    Map<String, dynamic> header,
    Map<String, Map<String, dynamic>> records,
    String family,
  ) {
    if (header['schemaVersion'] != 2) return header;
    final details = _details(header, records);
    final result = {...header, 'schemaVersion': 1}
      ..remove('detailSetId')
      ..remove('detailCount')
      ..remove('detailHash');
    if (family == 'fund') {
      result['adjustments'] = details
          .where((v) => v['kind'] == 'fundAdjustment')
          .map((v) => v['payload'])
          .toList();
      result['drpLinks'] = details
          .where((v) => v['kind'] == 'fundDrp')
          .map((v) => v['payload'])
          .toList();
    } else {
      result['residencyPeriods'] = details
          .where((v) => v['kind'] == 'residency')
          .map((v) => v['payload'])
          .toList();
      result['i1Reviews'] = details
          .where((v) => v['kind'] == 'i1')
          .map((v) => v['payload'])
          .toList();
    }
    return result;
  }

  static void _owner(String uid) {
    if (uid.trim().isEmpty || uid.contains('/')) {
      throw const FormatException('Owner required.');
    }
  }

  static bool _validId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value);
  static bool _validPath(String path) {
    final p = path.split('/');
    if (p.length.isOdd ||
        p.any((v) => !_validId(v)) ||
        !collections.contains(p.first)) {
      return false;
    }
    if (p.length == 2) return true;
    if (p.length == 4) {
      return p[2] == 'revisions' &&
              [
                'investment_transactions',
                'investment_allocations',
                'managed_fund_statements',
                'tax_years',
              ].contains(p.first) ||
          p.first == 'tax_years' && ['items', 'snapshots'].contains(p[2]) ||
          ['revision_details', 'account_restores'].contains(p.first) &&
              p[2] == 'records';
    }
    return p.length == 6 &&
        p.first == 'tax_years' &&
        p[2] == 'items' &&
        p[4] == 'revisions';
  }

  static dynamic _encode(dynamic value) {
    if (value is Timestamp) {
      return {
        '__timestamp': [value.seconds, value.nanoseconds],
      };
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key as String, _encode(item)));
    }
    if (value is List) return value.map(_encode).toList();
    if (value == null ||
        value is String ||
        value is bool ||
        value is num && value.isFinite) {
      return value;
    }
    throw const FormatException('Unsupported backup field type.');
  }

  static dynamic _decode(dynamic value) {
    if (value is Map) {
      if (value.containsKey('__timestamp')) {
        final parts = value['__timestamp'];
        if (value.length != 1 ||
            parts is! List ||
            parts.length != 2 ||
            parts[0] is! int ||
            parts[1] is! int ||
            parts[1] < 0 ||
            parts[1] > 999999999) {
          throw const FormatException('Invalid timestamp encoding.');
        }
        return Timestamp(parts[0], parts[1]);
      }
      return value.map((key, item) => MapEntry(key as String, _decode(item)));
    }
    if (value is List) return value.map(_decode).toList();
    return value;
  }

  static void _walk(dynamic value, String uid, [int depth = 0]) {
    if (depth > 30) {
      throw const FormatException('Backup nesting exceeds limit.');
    }
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String ||
            [
              'pdfBytes',
              'pdfText',
              'accessToken',
              'refreshToken',
              'password',
            ].contains(entry.key) ||
            entry.key == 'userId' && entry.value != uid) {
          throw const FormatException('Sensitive or wrong-owner data.');
        }
        _walk(entry.value, uid, depth + 1);
      }
    } else if (value is List) {
      for (final item in value) {
        _walk(item, uid, depth + 1);
      }
    } else if (value != null &&
            value is! String &&
            value is! bool &&
            value is! num ||
        value is num && !value.isFinite) {
      throw const FormatException('Invalid JSON value.');
    }
  }
}

class AccountRestorePreview {
  final String hash;
  final int recordCount, transactions, funds, years, items;
  const AccountRestorePreview(
    this.hash,
    this.recordCount,
    this.transactions,
    this.funds,
    this.years,
    this.items,
  );
}
