import '../models/adviser_workpaper_decision.dart';
import '../models/tax_decimal.dart';
import 'tax_workspace_calculator.dart';

/// Only legal coverage can be supplied by an adviser. Missing documents, stale
/// inputs, invalid amounts and unreviewed facts cannot be waived by this path.
bool adviserCoverableIssue(String issue) {
  final text = issue.startsWith('capitalGains: ') ? issue.substring(14) : issue;
  return const {
    'Unsupported financial-year rule set requires tax review',
    'Unsupported financial-year rule set',
    'Foreign, temporary or unknown residency requires tax review',
    'Residency requires tax review',
    'Pre-CGT or indexed-era acquisitions require tax review',
    'Leap-day anniversary boundary requires tax review',
    'Confirm ordinary AUD investments with no special asset treatment',
    'I1 transition requires adviser review of all eligible assets and election effects; scenario is excluded from annual totals',
    'Capital activity requires a selected reviewed annual CGT worksheet',
    'Attributed fund gains require a selected annual CGT worksheet',
  }.contains(text);
}

TaxWorkspaceReport applyAdviserWorkpaperDecision({
  required TaxWorkspaceReport baseReport,
  required AdviserWorkpaperDecision decision,
  required String currentScopeFingerprint,
  int? currentYearStart,
}) {
  final invalid = decision.validation();
  if (currentYearStart != null && decision.yearStart != currentYearStart) {
    invalid.add('Adviser workpaper belongs to a different financial year');
  }
  if (decision.sourceFingerprint != currentScopeFingerprint) {
    invalid.add(
      'Adviser workpaper is stale: financial sources or review scope changed',
    );
  }
  if (decision.legalIssuesCovered.any(
    (issue) => !adviserCoverableIssue(issue),
  )) {
    invalid.add(
      'Adviser workpaper cannot waive document, amount or source-review requirements',
    );
  }
  final eligible = invalid.isEmpty;
  final remaining = [
    for (final issue in baseReport.issues)
      if (!eligible || !decision.legalIssuesCovered.contains(issue)) issue,
    ...invalid,
  ];
  final effectiveTotals = eligible
      ? decision.totals
      : baseReport.categoryTotals;
  return TaxWorkspaceReport(
    categoryTotals: effectiveTotals,
    issues: remaining,
    sectionIssues: baseReport.sectionIssues.map(
      (key, values) => MapEntry(
        key,
        values
            .where(
              (value) =>
                  !eligible ||
                  !decision.legalIssuesCovered.contains('$key: $value'),
            )
            .toList(),
      ),
    ),
    contributions: [
      ...baseReport.contributions,
      {
        'section': 'adviserWorkpaper',
        'kind': 'adviserSuppliedCompleteAnnualTotals',
        'applied': eligible,
        'decision': decision.toMap(),
        'replacesTotalsOnce': true,
        'changes': {
          for (final key in effectiveTotals.keys)
            key:
                (TaxDecimal.parse(effectiveTotals[key]!) -
                        TaxDecimal.parse(baseReport.categoryTotals[key] ?? '0'))
                    .toString(),
        },
      },
    ],
    i1Scenarios: baseReport.i1Scenarios,
    sourceFingerprint: baseReport.sourceFingerprint,
    canFinalise: remaining.isEmpty,
    workspaceGeneration: baseReport.workspaceGeneration,
    investmentGeneration: baseReport.investmentGeneration,
  );
}
