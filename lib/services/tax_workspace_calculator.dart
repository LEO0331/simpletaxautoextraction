import '../models/investment_ledger.dart';
import '../models/managed_fund_statement.dart';
import '../models/tax_decimal.dart';
import '../models/tax_record.dart';
import '../models/tax_workspace.dart';
import 'tax_rule_registry.dart';

class TaxWorkspaceReport {
  final Map<String, String> categoryTotals;
  final List<String> issues;
  final Map<String, List<String>> sectionIssues;
  final List<Map<String, dynamic>> contributions, i1Scenarios;
  final String sourceFingerprint;
  final bool canFinalise;
  final int workspaceGeneration, investmentGeneration;
  TaxWorkspaceReport({
    required Map<String, String> categoryTotals,
    required List<String> issues,
    required Map<String, List<String>> sectionIssues,
    required List<Map<String, dynamic>> contributions,
    required List<Map<String, dynamic>> i1Scenarios,
    required this.sourceFingerprint,
    required this.canFinalise,
    this.workspaceGeneration = 0,
    this.investmentGeneration = 0,
  }) : categoryTotals = Map.unmodifiable(categoryTotals),
       issues = List.unmodifiable(issues),
       sectionIssues = Map.unmodifiable(
         sectionIssues.map((k, v) => MapEntry(k, List<String>.unmodifiable(v))),
       ),
       contributions = List.unmodifiable(contributions.map(freezeTaxSnapshot)),
       i1Scenarios = List.unmodifiable(i1Scenarios.map(freezeTaxSnapshot));
  Map<String, dynamic> toMap() => freezeTaxSnapshot({
    'schemaVersion': 1,
    'calculationVersion': 'tax-workspace-v1',
    'categoryTotals': categoryTotals,
    'issues': issues,
    'sectionIssues': sectionIssues,
    'contributions': contributions,
    'i1Scenarios': i1Scenarios,
    'sourceFingerprint': sourceFingerprint,
    'canFinalise': canFinalise,
    'workspaceGeneration': workspaceGeneration,
    'investmentGeneration': investmentGeneration,
  });
}

/// Reconciled worksheet totals. This does not calculate tax liability or lodge a return.
class TaxWorkspaceCalculator {
  TaxWorkspaceReport calculate({
    required TaxWorkspace workspace,
    required List<TaxWorkspaceItem> items,
    required List<TaxRecord> rentals,
    required List<ManagedFundStatement> fundStatements,
    Map<String, dynamic>? cgtSnapshot,
    required int currentInvestmentGeneration,
    required int workspaceGeneration,
    DateTime? investmentHistoryStart,
    bool hasCapitalActivity = false,
    List<String> investmentIssues = const [],
  }) {
    final totals = {for (final k in taxWorkspaceTotals) k: TaxDecimal.zero};
    final issues = <String>[...workspace.validation()];
    if (!TaxRuleRegistry.supports(workspace.yearStart)) {
      issues.add('Unsupported financial-year rule set requires tax review');
    }
    final sections = <String, List<String>>{
      for (final k in taxWorkspaceSections) k: [],
    };
    final contributions = <Map<String, dynamic>>[],
        scenarios = <Map<String, dynamic>>[];
    final counts = {for (final k in taxWorkspaceSections) k: 0};
    final year = TaxYear(workspace.yearStart);
    void problem(String section, String message) {
      sections[section]!.add(message);
      issues.add('$section: $message');
    }

    void add(String key, TaxDecimal value) {
      totals[key] = totals[key]! + value;
    }

    for (final issue in investmentIssues) {
      problem('capitalGains', issue);
    }
    if (hasCapitalActivity && workspace.cgtSnapshotId.isEmpty) {
      problem(
        'capitalGains',
        'Capital activity requires a selected reviewed annual CGT worksheet',
      );
      counts['capitalGains'] = 1;
    }

    final sources = <String>{}, rentalIds = <String>{};
    final activeItems = items
        .where((i) => !i.isVoided && i.yearStart == workspace.yearStart)
        .toList();
    for (final item in activeItems) {
      final section = item.category == 'rentalReview'
          ? 'rental'
          : item.category;
      if (!sections.containsKey(section)) {
        issues.add('Unsupported item category');
        continue;
      }
      counts[section] = counts[section]! + 1;
      if (item.userId != workspace.userId) {
        problem(section, 'Source belongs to another user');
        continue;
      }
      final invalid = item.validation();
      if (invalid.isNotEmpty) {
        for (final p in invalid) {
          problem(section, p);
        }
        continue;
      }
      if (!sources.add('${item.category}|${item.sourceReference.trim()}')) {
        problem(section, 'Repeated source identity');
        continue;
      }
      if (!item.isReviewed) {
        problem(section, 'Source has not been reviewed');
        continue;
      }
      if (section == 'rental') {
        if (!rentalIds.add(item.rentalRecordId)) {
          problem(section, 'Rental record linked more than once');
          continue;
        }
        final matches = rentals
            .where((r) => r.id == item.rentalRecordId)
            .toList();
        if (matches.length != 1 ||
            matches.single.userId != workspace.userId ||
            matches.single.financialYear != year.toString() ||
            taxRecordFingerprint(matches.single) != item.rentalFingerprint) {
          problem(
            section,
            'Rental source is missing, changed or belongs to another year/user',
          );
          continue;
        }
        final rental = matches.single;
        if (rental.income.keys.any(
              (k) => !TaxRecord.incomeCategoryOptions.contains(k),
            ) ||
            rental.expenses.keys.any(
              (k) => !TaxRecord.expenseCategoryOptions.contains(k),
            )) {
          problem(section, 'Unknown rental categories require review');
          continue;
        }
        TaxDecimal exact(double n) {
          if (!n.isFinite ||
              n < 0 ||
              ((n * 100) - (n * 100).roundToDouble()).abs() > 0.000001) {
            throw const FormatException(
              'Rental amounts require nonnegative whole cents',
            );
          }
          return TaxDecimal.parse(n.toStringAsFixed(2));
        }

        try {
          final share = TaxDecimal.parse(item.ownershipPercent);
          final income =
              (rental.income.values.fold(
                        TaxDecimal.zero,
                        (a, v) => a + exact(v),
                      ) *
                      share)
                  .divide(TaxDecimal.parse('100'));
          final expenses =
              (rental.expenses.values.fold(
                        TaxDecimal.zero,
                        (a, v) => a + exact(v),
                      ) *
                      share)
                  .divide(TaxDecimal.parse('100'));
          add('rentalIncome', income);
          add('rentalDeductions', expenses);
          add('rentalNet', income - expenses);
          contributions.add({
            'section': section,
            'itemId': item.id,
            'sourceReference': item.sourceReference,
            'rentalRecordId': rental.id,
            'rentalFingerprint': item.rentalFingerprint,
            'ownershipPercent': item.ownershipPercent,
            'income': income.toString(),
            'deductions': expenses.toString(),
            'net': (income - expenses).toString(),
          });
        } on FormatException catch (e) {
          problem(section, e.message);
        }
        continue;
      }
      final amount = TaxDecimal.parse(item.amount);
      final target = {
        'salary': 'salaryIncome',
        'interest': 'interestIncome',
        'dividends': 'dividendIncome',
        'otherIncome': 'otherIncome',
        'deductions': 'deductions',
        'offsets': 'otherOffsets',
      }[section]!;
      add(target, amount);
      add('deductions', TaxDecimal.parse(item.deductions));
      add('withholding', TaxDecimal.parse(item.withholding));
      add('frankingCredits', TaxDecimal.parse(item.frankingCredits));
      add('otherOffsets', TaxDecimal.parse(item.taxOffset));
      if (!TaxDecimal.parse(item.deductions).isZero) {
        counts['deductions'] = counts['deductions']! + 1;
      }
      if (!TaxDecimal.parse(item.taxOffset).isZero ||
          !TaxDecimal.parse(item.frankingCredits).isZero) {
        counts['offsets'] = counts['offsets']! + 1;
      }
      contributions.add({
        'section': section,
        'itemId': item.id,
        ...item.toMap(),
      });
    }
    for (final rental in rentals.where(
      (r) => r.financialYear == year.toString() && r.userId == workspace.userId,
    )) {
      if (!rentalIds.contains(rental.id)) {
        problem(
          'rental',
          'A rental record has no reviewed ownership/source link',
        );
      }
    }
    final fundIds = <String>{};
    for (final f in fundStatements.where(
      (f) => !f.isVoided && f.yearStart == workspace.yearStart,
    )) {
      counts['funds'] = counts['funds']! + 1;
      if (f.userId != workspace.userId || !fundIds.add(f.identity)) {
        problem('funds', 'Wrong owner or duplicate fund statement');
        continue;
      }
      final invalid = f.validation();
      if (!f.isReviewed || invalid.isNotEmpty) {
        problem('funds', 'Fund statement requires review and reconciliation');
        continue;
      }
      for (final entry in {
        'australianIncome': 'fundAustralianIncome',
        'foreignIncome': 'fundForeignIncome',
        'frankingCredits': 'frankingCredits',
        'foreignTaxOffset': 'foreignTaxOffset',
        'withholding': 'withholding',
      }.entries) {
        add(entry.value, f.component(entry.key));
      }
      if (!f.component('frankingCredits').isZero ||
          !f.component('foreignTaxOffset').isZero) {
        counts['offsets'] = counts['offsets']! + 1;
      }
      contributions.add({
        'section': 'funds',
        'statementId': f.id,
        'revision': f.revision,
        'sourceReference': f.sourceReference,
        'components': f.components,
        'capitalGainsIncludedViaSnapshotOnly': true,
      });
      if (!f.component('grossCapitalGain').isZero &&
          workspace.cgtSnapshotId.isEmpty) {
        problem(
          'capitalGains',
          'Attributed fund gains require a selected annual CGT worksheet',
        );
      }
    }
    if (workspace.cgtSnapshotId.isNotEmpty) {
      counts['capitalGains'] = 1;
      final result = Map<String, dynamic>.from(
        cgtSnapshot?['result'] as Map? ??
            cgtSnapshot?['annualResult'] as Map? ??
            {},
      );
      // Existing investment snapshots embed the annual result under annualCgt.
      final cgt = result.isNotEmpty
          ? result
          : Map<String, dynamic>.from(
              cgtSnapshot?['annualCgt'] as Map? ?? cgtSnapshot ?? {},
            );
      final context = Map<String, dynamic>.from(
        (cgt['snapshot'] as Map?)?['context'] as Map? ?? {},
      );
      final valid =
          cgtSnapshot?['id'] == workspace.cgtSnapshotId &&
          cgtSnapshot?['userId'] == workspace.userId &&
          cgtSnapshot?['ledgerGeneration'] == currentInvestmentGeneration &&
          cgt['year'] == year.toString() &&
          cgt['status'] == 'ReviewedWorksheet' &&
          (cgt['issues'] as List? ?? []).isEmpty &&
          [
            'confirmedContinuousResident',
            'confirmedNonTemporaryResident',
            'completeHistory',
            'noPendingFundAdjustments',
            'priorLossesReviewed',
            'confirmedSupportedAssets',
          ].every((k) => context[k] == true);
      final net = cgt['netCapitalGain'];
      bool exactNet = false;
      if (net is String) {
        try {
          exactNet = !TaxDecimal.parse(net).isNegative;
        } on FormatException {
          exactNet = false;
        }
      }
      if (!valid || !exactNet || net is! String) {
        problem(
          'capitalGains',
          'Annual CGT snapshot is missing, stale or not a supported reviewed worksheet',
        );
      } else {
        add('netCapitalGain', TaxDecimal.parse(net));
        contributions.add({
          'section': 'capitalGains',
          'snapshotId': workspace.cgtSnapshotId,
          'ledgerGeneration': currentInvestmentGeneration,
          'netCapitalGain': net,
        });
      }
      if (investmentHistoryStart == null) {
        problem(
          'capitalGains',
          'Investment history start requires evidence before residency continuity can be checked',
        );
      }
    }
    final periodValidation = workspace.residencyPeriods
        .expand((p) => p.validation())
        .toList();
    if (periodValidation.isEmpty) {
      final periods = [...workspace.residencyPeriods]
        ..sort((a, b) => a.start.compareTo(b.start));
      final neededStart =
          workspace.cgtSnapshotId.isNotEmpty &&
              investmentHistoryStart != null &&
              investmentHistoryStart.isBefore(year.start)
          ? DateTime.utc(
              investmentHistoryStart.year,
              investmentHistoryStart.month,
              investmentHistoryStart.day,
            )
          : year.start;
      var cursor = neededStart;
      DateTime? previousEnd;
      for (final p in periods) {
        final start = workspaceDate(p.start),
            end = workspaceDate(p.endExclusive);
        if (!p.reviewed || p.evidence.trim().isEmpty) {
          issues.add('Residency periods require reviewed evidence');
        }
        if (p.classification != 'resident') {
          issues.add(
            'Foreign, temporary or unknown residency requires tax review',
          );
        }
        if (start.isAfter(cursor) && cursor.isBefore(year.endExclusive)) {
          issues.add('Residency timeline has a gap');
        }
        if (previousEnd != null && start.isBefore(previousEnd)) {
          issues.add('Residency timeline overlaps');
        }
        if (previousEnd == null || end.isAfter(previousEnd)) previousEnd = end;
        if (end.isAfter(cursor)) cursor = end;
      }
      if (cursor.isBefore(year.endExclusive)) {
        issues.add(
          'Residency timeline does not cover the required history through year end',
        );
      }
    }
    final elections = <String, Set<String>>{}, assets = <String>{};
    for (final i in workspace.i1Reviews) {
      if (!assets.add('${i.date}|${i.assetReference}')) {
        issues.add('Repeated I1 asset');
      }
      if (i.validation().isNotEmpty) continue;
      elections.putIfAbsent(i.date, () => {}).add(i.election);
      final market = TaxDecimal.parse(i.marketValue),
          cost = TaxDecimal.parse(i.costBase),
          reduced = TaxDecimal.parse(i.reducedCostBase);
      scenarios.add({
        'date': i.date,
        'assetReference': i.assetReference,
        'classification': i.classification,
        'election': i.election,
        'undiscountedGain': (market > cost ? market - cost : TaxDecimal.zero)
            .toString(),
        'capitalLoss': (market < reduced ? reduced - market : TaxDecimal.zero)
            .toString(),
        'includedInAnnualCgt':
            i.adviserDecision != null &&
            (((cgtSnapshot?['snapshot'] as Map?)?['i1Reviews'] as List?) ?? [])
                .any(
                  (review) =>
                      review is Map &&
                      canonicalTaxFingerprint(
                            Map<String, dynamic>.from(review),
                          ) ==
                          canonicalTaxFingerprint(i.toMap()),
                ),
        if (i.adviserDecision != null)
          'adviserDecision': i.adviserDecision!.toMap(),
      });
      if (scenarios.last['includedInAnnualCgt'] != true) {
        issues.add(
          'I1 transition requires adviser review of all eligible assets and election effects; scenario is excluded from annual totals',
        );
      }
    }
    if (elections.values.any(
      (v) => v.contains('recognise') && v.contains('deferAllEligible'),
    )) {
      issues.add(
        'I1 deferral election covers all eligible assets at the event; mixed choices are invalid',
      );
    }
    for (final section in taxWorkspaceSections) {
      final state = workspace.sectionStates[section] ?? 'notStarted';
      if (!['reconciled', 'notApplicable'].contains(state)) {
        problem(section, 'Section is not reconciled');
      }
      if ((workspace.sectionEvidence[section] ?? '').trim().isEmpty) {
        problem(
          section,
          'Completeness or non-applicability evidence is required',
        );
      }
      if (state == 'notApplicable' && counts[section]! > 0) {
        problem(
          section,
          'Section contains sources and cannot be marked not applicable',
        );
      }
      if (state == 'reconciled' && counts[section] == 0) {
        problem(
          section,
          'No reviewed source: use not applicable with evidence for a zero-source section',
        );
      }
    }
    for (final e in workspace.prefill.entries) {
      if (totals.containsKey(e.key) &&
          workspaceMoney(e.value, signed: e.key == 'rentalNet') &&
          TaxDecimal.parse(e.value) != totals[e.key]) {
        issues.add('Prefill mismatch for ${e.key}');
      }
    }
    final sortedItems = [...items]
      ..sort(
        (a, b) =>
            (a.id ?? a.sourceReference).compareTo(b.id ?? b.sourceReference),
      );
    final sortedRentals = [...rentals]
      ..sort((a, b) => (a.id ?? a.propertyId).compareTo(b.id ?? b.propertyId));
    final sortedFunds = [...fundStatements]
      ..sort((a, b) => a.identity.compareTo(b.identity));
    final config = workspace.toMap()
      ..remove('status')
      ..remove('revision')
      ..remove('amendmentReason');
    final fingerprint = canonicalTaxFingerprint({
      'workspace': config,
      'items': sortedItems.map((i) => {'id': i.id, ...i.toMap()}).toList(),
      'rentals': sortedRentals.map((r) => {'id': r.id, ...r.toMap()}).toList(),
      'funds': sortedFunds.map((f) => {'id': f.id, ...f.toMap()}).toList(),
      'cgtSnapshot': cgtSnapshot,
      'investmentGeneration': currentInvestmentGeneration,
      'hasCapitalActivity': hasCapitalActivity,
      'investmentIssues': [...investmentIssues]..sort(),
      'workspaceGeneration': workspaceGeneration,
      'investmentHistoryStart': investmentHistoryStart
          ?.toUtc()
          .toIso8601String(),
    });
    return TaxWorkspaceReport(
      categoryTotals: totals.map((k, v) => MapEntry(k, v.toString())),
      issues: issues.toSet().toList(),
      sectionIssues: sections,
      contributions: contributions,
      i1Scenarios: scenarios,
      sourceFingerprint: fingerprint,
      canFinalise: issues.isEmpty,
      workspaceGeneration: workspaceGeneration,
      investmentGeneration: currentInvestmentGeneration,
    );
  }
}
