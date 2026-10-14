import 'tax_rule_registry.dart';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/investment_ledger.dart';
import '../models/document_coverage.dart';
import 'holdings_reconciler.dart';
import '../models/managed_fund_statement.dart';
import '../models/tax_record.dart';
import '../models/tax_decimal.dart';
import '../models/tax_workspace.dart';
import 'firestore_service.dart';
import 'investment_parcel_ledger.dart';
import 'tax_workspace_calculator.dart';
import 'tax_workspace_service.dart';

class TaxWorkspaceBundle {
  final TaxWorkspace workspace;
  final List<TaxWorkspaceItem> items;
  final List<TaxRecord> rentals;
  final List<ManagedFundStatement> fundStatements;
  final List<Map<String, dynamic>> cgtSnapshots;
  final TaxWorkspaceReport report;
  final int workspaceGeneration, investmentGeneration;
  final DateTime? investmentHistoryStart;
  final bool hasCapitalActivity;
  final List<String> investmentIssues;
  final Map<String, dynamic> auditSources;
  const TaxWorkspaceBundle({
    required this.workspace,
    required this.items,
    required this.rentals,
    required this.fundStatements,
    required this.cgtSnapshots,
    required this.report,
    required this.workspaceGeneration,
    required this.investmentGeneration,
    required this.investmentHistoryStart,
    required this.hasCapitalActivity,
    required this.investmentIssues,
    required this.auditSources,
  });
}

/// Consistent source loading, workpaper finalisation, and owner-bound backups.
class TaxWorkspaceCoordinator {
  final TaxWorkspaceService workspaces;
  final FirestoreService sources;
  TaxWorkspaceCoordinator({required this.workspaces, required this.sources});

  Future<TaxWorkspaceBundle> load(String uid, int yearStart) async {
    final generation = await workspaces.getGeneration(uid);
    final investmentGeneration = await sources.getInvestmentLedgerGeneration(
      uid,
    );
    final workspace =
        await workspaces.getWorkspace(uid, yearStart) ??
        TaxWorkspace(userId: uid, yearStart: yearStart);
    final items = await workspaces.getItems(uid, yearStart);
    final coverage = await workspaces.getDocumentCoverage(uid, yearStart);
    final documentIssues = coverageIssues(coverage);
    final rentals = (await sources.getUserTaxRecords(uid).first)
        .where((r) => r.financialYear == TaxYear(yearStart).toString())
        .toList();
    final funds = await sources.getManagedFundStatementsOnce(uid);
    final transactions = await sources.getInvestmentTransactionsOnce(
      uid,
      includeVoided: true,
    );
    final allocations = await sources.getInvestmentAllocationsOnce(uid);
    final snapshots = await sources.getInvestmentCalculationSnapshotsOnce(uid);
    Map<String, dynamic>? selected;
    if (workspace.cgtSnapshotId.isNotEmpty) {
      selected =
          snapshots
              .where((s) => s['id'] == workspace.cgtSnapshotId)
              .firstOrNull ??
          await sources.getInvestmentCalculationSnapshotOnce(
            uid,
            workspace.cgtSnapshotId,
          );
      if (selected != null &&
          !snapshots.any((s) => s['id'] == selected!['id'])) {
        snapshots.add(selected);
      }
    }
    final earlier =
        (await workspaces.getWorkspaces(uid))
            .where((w) => w.yearStart < yearStart && w.cgtSnapshotId.isNotEmpty)
            .toList()
          ..sort((a, b) => b.yearStart.compareTo(a.yearStart));
    final priorIssues = <String>[];
    Map<String, dynamic>? anchor;
    if (earlier.isNotEmpty) {
      final prior = earlier.first;
      final priorSnapshot = await sources.getInvestmentCalculationSnapshotOnce(
        uid,
        prior.cgtSnapshotId,
      );
      final annual = (priorSnapshot?['annualCgt'] as Map?) ?? priorSnapshot;
      final closing = (annual?['snapshot'] as Map?)?['closingLossBalances'];
      anchor = {
        'userId': uid,
        'yearStart': prior.yearStart,
        'revision': prior.revision,
        'status': prior.status,
        'snapshotId': prior.cgtSnapshotId,
        'closingLossBalances': closing,
      };
      if (prior.yearStart != yearStart - 1) {
        priorIssues.add(
          'Intervening capital-loss years require reviewed workpapers before losses can roll forward',
        );
      }
      if (priorSnapshot?['ledgerGeneration'] != investmentGeneration ||
          annual?['year'] != TaxYear(prior.yearStart).toString() ||
          annual?['status'] != 'ReviewedWorksheet') {
        priorIssues.add(
          'Earlier capital-loss worksheet is stale or unsupported; recalculate and review it',
        );
      }
      if (prior.status == 'draft' && prior.amendmentReason.isNotEmpty) {
        priorIssues.add(
          'An earlier capital-loss year is under amendment; reconcile it before reviewing later losses',
        );
      }
      if (closing is! List || priorSnapshot?['userId'] != uid) {
        priorIssues.add(
          'Earlier capital-loss worksheet lacks a matching structured closing balance',
        );
      } else {
        try {
          final expected = _lossBalances(
            closing,
            closing: true,
            maxOriginYear: prior.yearStart,
          );
          if (selected == null && expected.isNotEmpty) {
            priorIssues.add(
              'Prior capital losses require an annual CGT worksheet even with no current disposal',
            );
          } else if (selected != null) {
            final currentAnnual = (selected['annualCgt'] as Map?) ?? selected;
            final context =
                (currentAnnual['snapshot'] as Map?)?['context'] as Map?;
            final opening = _lossBalances(
              context?['priorLossBalances'] as List? ?? [],
              maxOriginYear: yearStart - 1,
            );
            if (canonicalTaxFingerprint(expected) !=
                canonicalTaxFingerprint(opening)) {
              priorIssues.add(
                'Opening capital losses no longer match the earlier reviewed worksheet; recompute and review annual CGT',
              );
            }
            final sum = opening.values.fold(
              TaxDecimal.zero,
              (a, v) => a + TaxDecimal.parse(v),
            );
            if (sum != TaxDecimal.parse(context?['priorLosses'] as String)) {
              priorIssues.add(
                'Opening capital-loss total does not match its originating balances',
              );
            }
          }
        } catch (_) {
          priorIssues.add(
            'Capital-loss dependencies require valid originating years and exact amounts',
          );
        }
      }
      if (selected != null) {
        selected = {...selected, 'priorLossAnchor': anchor};
        final index = snapshots.indexWhere((s) => s['id'] == selected!['id']);
        if (index >= 0) snapshots[index] = selected;
      }
    }
    if (generation != await workspaces.getGeneration(uid) ||
        investmentGeneration !=
            await sources.getInvestmentLedgerGeneration(uid)) {
      throw StateError('Source records changed while loading. Reload.');
    }
    final year = TaxYear(yearStart);
    final acquisitions =
        transactions
            .where(
              (t) =>
                  !t.isVoided &&
                  t.isBuy &&
                  t.tradeDate.isBefore(year.endExclusive),
            )
            .map((t) => t.tradeDate)
            .toList()
          ..sort();
    final historyStart = acquisitions.firstOrNull;
    final ledger = InvestmentParcelLedger().replay(
      transactions: transactions,
      allocations: allocations,
      statements: funds,
      asOfDate: DateTime.utc(yearStart + 1, 6, 30),
    );
    for (final observation in coverage.where(
      (r) => r.family.endsWith('Holdings') && r.state == 'reviewed',
    )) {
      final cutoff = parseDocumentDate(observation.observationDateIso);
      if (cutoff == null) {
        documentIssues.add('Holdings observation date requires review.');
        continue;
      }
      documentIssues.addAll(
        reconcileHoldings(
          observation,
          InvestmentParcelLedger().replay(
            transactions: transactions,
            allocations: allocations,
            statements: funds,
            asOfDate: cutoff,
          ),
        ),
      );
    }
    documentIssues.addAll(
      knownDocumentCoverageIssues(coverage, [
        for (final t in transactions.where(
          (t) => !t.isVoided && year.contains(t.tradeDate),
        ))
          {
            'domain': 'investment_transactions',
            'id': t.id ?? '',
            'account': t.accountNumber ?? '',
            'ticker': t.ticker,
            'family': 'brokerTrade',
            'sourceHash': t.sourceHash ?? '',
          },
        for (final f in funds.where(
          (f) => !f.isVoided && f.yearStart == yearStart,
        ))
          {
            'domain': 'managed_fund_statements',
            'id': f.id ?? '',
            'account': f.accountNumber,
            'ticker': f.ticker,
            'family': 'fundAnnual',
          },
      ]),
    );
    final capitalActivity =
        transactions.any(
          (t) => !t.isVoided && t.isSell && year.contains(t.tradeDate),
        ) ||
        ledger.fundGains.any((g) => year.contains(g.date));
    final report = TaxWorkspaceCalculator().calculate(
      workspace: workspace,
      items: items,
      rentals: rentals,
      fundStatements: funds,
      cgtSnapshot: selected,
      currentInvestmentGeneration: investmentGeneration,
      workspaceGeneration: generation,
      investmentHistoryStart: historyStart,
      hasCapitalActivity: capitalActivity,
      investmentIssues: [...ledger.issues, ...priorIssues, ...documentIssues],
    );
    final audit = freezeTaxSnapshot(
      Map<String, dynamic>.from(
        _jsonValue({
              'rentals': rentals
                  .map((r) => {'id': r.id, ...r.toMap()})
                  .toList(),
              'fundStatements': funds
                  .map((f) => {'id': f.id, ...f.toMap()})
                  .toList(),
              'transactions': transactions
                  .map((t) => {'id': t.id, ...t.toMap()})
                  .toList(),
              'allocations': allocations.map((a) => a.toMap()).toList(),
              'cgtSnapshot': selected,
              'priorLossAnchor': anchor,
              'documentCoverage': coverage.map((r) => r.toMap()).toList(),
            })
            as Map,
      ),
    );
    return TaxWorkspaceBundle(
      workspace: workspace,
      items: List.unmodifiable(items),
      rentals: List.unmodifiable(rentals),
      fundStatements: List.unmodifiable(funds),
      cgtSnapshots: List.unmodifiable(snapshots),
      report: report,
      workspaceGeneration: generation,
      investmentGeneration: investmentGeneration,
      investmentHistoryStart: historyStart,
      hasCapitalActivity: capitalActivity,
      investmentIssues: List.unmodifiable([
        ...ledger.issues,
        ...priorIssues,
        ...documentIssues,
      ]),
      auditSources: audit,
    );
  }

  Future<TaxWorkspaceBundle> _fresh(TaxWorkspaceBundle bundle) async {
    final current = await load(
      bundle.workspace.userId,
      bundle.workspace.yearStart,
    );
    if (current.workspace.revision != bundle.workspace.revision ||
        current.report.sourceFingerprint != bundle.report.sourceFingerprint) {
      throw StateError(
        'Sources or review inputs changed. Reload the workspace.',
      );
    }
    return current;
  }

  Future<void> finalise(TaxWorkspaceBundle bundle) async {
    final current = await _fresh(bundle);
    if (!current.report.canFinalise ||
        current.workspace.status == 'finalised') {
      throw StateError(
        'Reconcile all sections and review issues before finalising.',
      );
    }
    final finalised = current.workspace.copyWith(status: 'finalised');
    final selected = current.cgtSnapshots
        .where((s) => s['id'] == finalised.cgtSnapshotId)
        .firstOrNull;
    // The finalisation write itself advances generation. Freeze the projection
    // of that committed state so a freshly finalised year is not immediately stale.
    final report = TaxWorkspaceCalculator().calculate(
      workspace: finalised,
      items: current.items,
      rentals: current.rentals,
      fundStatements: current.fundStatements,
      cgtSnapshot: selected,
      currentInvestmentGeneration: current.investmentGeneration,
      workspaceGeneration: current.workspaceGeneration + 1,
      investmentHistoryStart: current.investmentHistoryStart,
      hasCapitalActivity: current.hasCapitalActivity,
      investmentIssues: current.investmentIssues,
    );
    await workspaces.saveWorkspace(
      finalised,
      finalSnapshot: {
        'sourceFingerprint': report.sourceFingerprint,
        'report': report.toMap(),
        'workspace': finalised
            .copyWith(revision: finalised.revision + 1)
            .toMap(),
        'items': current.items.map((i) => {'id': i.id, ...i.toMap()}).toList(),
        'sources': current.auditSources,
      },
      expectedWorkspaceGeneration: current.workspaceGeneration,
      expectedInvestmentGeneration: current.investmentGeneration,
    );
  }

  String exportWorksheet(TaxWorkspaceBundle bundle) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': 'au-tax-review-workpaper',
        'version': 1,
        'userId': bundle.workspace.userId,
        'yearStart': bundle.workspace.yearStart,
        'workspace': bundle.workspace.toMap(),
        'report': bundle.report.toMap(),
        'sources': bundle.auditSources,
      });

  Future<String> exportBackup(TaxWorkspaceBundle bundle) async {
    final current = await _fresh(bundle);
    final snapshots = await workspaces.getSnapshots(
      current.workspace.userId,
      current.workspace.yearStart,
      all: true,
    );
    final history = await workspaces.getAuditHistory(
      current.workspace.userId,
      current.workspace.yearStart,
    );
    if (current.workspaceGeneration !=
            await workspaces.getGeneration(current.workspace.userId) ||
        current.investmentGeneration !=
            await sources.getInvestmentLedgerGeneration(
              current.workspace.userId,
            )) {
      throw StateError('Sources changed while exporting the backup. Reload.');
    }
    final backup = const JsonEncoder.withIndent('  ').convert(
      _jsonValue({
        'format': 'au-tax-workspace-backup',
        'version': 1,
        'userId': current.workspace.userId,
        'yearStart': current.workspace.yearStart,
        'workspace': current.workspace.toMap(),
        'items': current.items.map((i) => i.toMap()).toList(),
        'sources': current.auditSources,
        'snapshots': snapshots,
        'history': history,
      }),
    );
    if (utf8.encode(backup).length > 32 * 1024 * 1024) {
      throw StateError(
        'Backup exceeds the 32 MB file safety limit. Export years separately.',
      );
    }
    return backup;
  }

  Future<int> restoreBackup(String uid, String text) async {
    if (utf8.encode(text).length > 32 * 1024 * 1024) {
      throw const FormatException(
        'Backup exceeds the 32 MB file safety limit.',
      );
    }
    late Map<String, dynamic> data;
    late TaxWorkspace restored;
    late List<TaxWorkspaceItem> items;
    late List<Map<String, dynamic>> snapshots;
    try {
      data = Map<String, dynamic>.from(jsonDecode(text) as Map);
      if (!_only(data, {
            'format',
            'version',
            'userId',
            'yearStart',
            'workspace',
            'items',
            'sources',
            'snapshots',
            'history',
          }) ||
          data['format'] != 'au-tax-workspace-backup' ||
          data['version'] != 1 ||
          data['userId'] != uid) {
        throw const FormatException();
      }
      restored = TaxWorkspace.fromMap(
        Map<String, dynamic>.from(data['workspace'] as Map),
      );
      if (restored.userId != uid ||
          restored.yearStart != data['yearStart'] ||
          !TaxRuleRegistry.supports(restored.yearStart) ||
          restored.validation().isNotEmpty) {
        throw const FormatException();
      }
      final entries = data['items'] as List;
      final archives = data['snapshots'] as List;
      if (data['sources'] is! Map) {
        throw const FormatException();
      }
      final history = Map<String, dynamic>.from(data['history'] as Map);
      if (!_only(history, {'workspaceRevisions', 'itemRevisions'})) {
        throw const FormatException();
      }
      for (final raw in history['workspaceRevisions'] as List) {
        final old = TaxWorkspace.fromMap(Map<String, dynamic>.from(raw as Map));
        if (old.userId != uid ||
            old.yearStart != restored.yearStart ||
            old.validation().isNotEmpty) {
          throw const FormatException();
        }
      }
      for (final revisions in (history['itemRevisions'] as Map).values) {
        for (final raw in revisions as List) {
          final old = TaxWorkspaceItem.fromMap(
            Map<String, dynamic>.from(raw as Map),
          );
          if (old.userId != uid ||
              old.yearStart != restored.yearStart ||
              old.validation().isNotEmpty) {
            throw const FormatException();
          }
        }
      }
      items = entries
          .map(
            (raw) =>
                TaxWorkspaceItem.fromMap(Map<String, dynamic>.from(raw as Map)),
          )
          .map((i) {
            if (i.validation().isNotEmpty) throw const FormatException();
            return TaxWorkspaceItem.fromMap({
              ...i.toMap(),
              'revision': 0,
              'isReviewed': false,
            });
          })
          .toList();
      final identities = <String>{};
      for (final item in items) {
        if (item.userId != uid ||
            item.yearStart != restored.yearStart ||
            item.validation().isNotEmpty ||
            !identities.add(
              canonicalTaxFingerprint([
                item.category,
                item.sourceReference.trim(),
              ]),
            )) {
          throw const FormatException();
        }
      }
      snapshots = archives
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      final audit = Map<String, dynamic>.from(data['sources'] as Map);
      final coreAudit = {...audit}..remove('documentCoverage');
      if (!_only(coreAudit, {
        'rentals',
        'fundStatements',
        'transactions',
        'allocations',
        'cgtSnapshot',
        'priorLossAnchor',
      })) {
        throw const FormatException();
      }
      if (audit.containsKey('documentCoverage')) {
        for (final raw in audit['documentCoverage'] as List) {
          final record = DocumentCoverage.fromMap(
            Map<String, dynamic>.from(raw as Map),
          );
          if (record.userId != uid ||
              record.taxYearStart != restored.yearStart ||
              record.validation().isNotEmpty) {
            throw const FormatException();
          }
        }
      }
      for (final key in ['rentals', 'fundStatements', 'transactions']) {
        for (final fact in audit[key] as List) {
          if (fact is! Map || fact['userId'] != uid) {
            throw const FormatException();
          }
        }
      }
      if (audit['allocations'] is! List ||
          (audit['cgtSnapshot'] != null &&
              (audit['cgtSnapshot'] is! Map ||
                  audit['cgtSnapshot']['userId'] != uid))) {
        throw const FormatException();
      }
      if (audit['priorLossAnchor'] != null &&
          (audit['priorLossAnchor'] is! Map ||
              audit['priorLossAnchor']['userId'] != uid)) {
        throw const FormatException();
      }
      for (final archive in snapshots) {
        if (archive['userId'] != uid ||
            archive['yearStart'] != restored.yearStart ||
            archive['payload'] is! Map) {
          throw const FormatException();
        }
      }
    } catch (_) {
      // JSON/decimal errors can contain source strings. Surface a fixed message.
      throw const FormatException(
        'Invalid, unsupported or wrong-owner workspace backup.',
      );
    }
    final restoreTag = 'Restored backup ${canonicalTaxFingerprint(data)}';
    final existing = await workspaces.getWorkspace(uid, restored.yearStart);
    if (existing != null &&
        (existing.status == 'finalised' ||
            existing.amendmentReason != restoreTag)) {
      throw StateError(
        'Restore needs a new year; existing workspaces are preserved.',
      );
    }
    final existingItems = await workspaces.getItems(uid, restored.yearStart);
    for (final current in existingItems) {
      final matching = items
          .where(
            (i) =>
                i.category == current.category &&
                i.sourceReference.trim() == current.sourceReference.trim(),
          )
          .firstOrNull;
      final financial = current.toMap()..remove('revision');
      final desired = matching == null
          ? null
          : (matching.toMap()..remove('revision'));
      if (desired == null ||
          canonicalTaxFingerprint(financial) !=
              canonicalTaxFingerprint(desired)) {
        throw StateError(
          'An interrupted restore has been edited. Existing facts are preserved.',
        );
      }
    }
    if (existing == null) {
      restored = TaxWorkspace.fromMap({
        ...restored.toMap(),
        'status': 'draft',
        'revision': 0,
        'amendmentReason': restoreTag,
        'cgtSnapshotId': '',
        'sectionStates': {
          for (final key in taxWorkspaceSections) key: 'needsReview',
        },
        'residencyPeriods': restored.residencyPeriods
            .map((p) => {...p.toMap(), 'reviewed': false})
            .toList(),
        'i1Reviews': restored.i1Reviews
            .map((i) => {...i.toMap(), 'reviewed': false})
            .toList(),
      });
      await workspaces.saveWorkspace(restored);
    }
    // Restore is resumable, not an all-or-nothing bulk overwrite. Every fact is
    // unreviewed and a partial network failure leaves an incomplete draft.
    for (final item in items) {
      await workspaces.saveItem(item);
    }
    await workspaces.importHistoricalSnapshot(
      uid,
      restored.yearStart,
      _sourceArchive(data),
    );
    for (final archive in snapshots) {
      await workspaces.importHistoricalSnapshot(
        uid,
        restored.yearStart,
        archive['kind'] == 'imported'
            ? Map<String, dynamic>.from(archive['payload'] as Map)
            : archive,
      );
    }
    return restored.yearStart;
  }
}

Map<String, dynamic> _sourceArchive(Map<String, dynamic> backup) => {
  'schemaVersion': 1,
  'kind': 'backup-source-audit',
  'userId': backup['userId'],
  'yearStart': backup['yearStart'],
  'originalWorkspace': backup['workspace'],
  'originalItems': backup['items'],
  'sources': backup['sources'],
  'history': backup['history'],
};

Map<String, String> _lossBalances(
  List raw, {
  bool closing = false,
  required int maxOriginYear,
}) {
  final result = <String, String>{};
  final seen = <int>{};
  for (final row in raw) {
    if (row is! Map) throw const FormatException();
    final origin = row['originStartYear'];
    final amount = row[closing ? 'remainingAmount' : 'amount'];
    if (origin is! int ||
        origin < 1900 ||
        origin > maxOriginYear ||
        !seen.add(origin) ||
        amount is! String ||
        !workspaceMoney(amount)) {
      throw const FormatException();
    }
    final value = TaxDecimal.parse(amount);
    if (!value.isZero) result['$origin'] = value.toString();
  }
  return result;
}

bool _only(Map<String, dynamic> value, Set<String> allowed) =>
    value.keys.every(allowed.contains) &&
    value.keys.toSet().containsAll(allowed);

dynamic _jsonValue(dynamic value) {
  if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is double && !value.isFinite) return 'invalid-nonfinite';
  if (value is Map) {
    return value.map((key, entry) => MapEntry('$key', _jsonValue(entry)));
  }
  if (value is List) return value.map(_jsonValue).toList();
  return value;
}
