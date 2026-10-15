import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/adviser_workpaper_decision.dart';
import 'package:simpletaxautoextraction/models/tax_workspace.dart';
import 'package:simpletaxautoextraction/services/adviser_workpaper_decision_service.dart';
import 'package:simpletaxautoextraction/services/tax_workspace_calculator.dart';

void main() {
  final hash = List.filled(64, 'a').join();
  final totals = {for (final key in taxWorkspaceTotals) key: '0'};
  TaxWorkspaceReport report(List<String> issues) => TaxWorkspaceReport(
    categoryTotals: {...totals, 'netCapitalGain': '100'},
    issues: issues,
    sectionIssues: {'capitalGains': []},
    contributions: [],
    i1Scenarios: [],
    sourceFingerprint: hash,
    canFinalise: issues.isEmpty,
  );
  AdviserWorkpaperDecision decision({
    String? source,
    List<String>? covered,
    Map<String, String>? amounts,
  }) => AdviserWorkpaperDecision(
    yearStart: 2027,
    sourceFingerprint: source ?? hash,
    adviserReference: 'Synthetic adviser',
    evidenceReference: 'Synthetic complete annual workpaper',
    ruleVersion: 'Adviser determination 2027 v1',
    totals: amounts ?? {...totals, 'netCapitalGain': '75.005'},
    legalIssuesCovered:
        covered ?? ['Unsupported financial-year rule set requires tax review'],
    reviewed: true,
    completeSources: true,
    closingLossBalances: [
      const AdviserClosingLossBalance(
        originStartYear: 2020,
        amount: '10',
        evidenceReference: 'Reviewed loss register',
      ),
    ],
  );
  test(
    'Complete adviser totals replace once, retain half cents and closing loss provenance',
    () {
      final result = applyAdviserWorkpaperDecision(
        baseReport: report([
          'Unsupported financial-year rule set requires tax review',
        ]),
        decision: decision(),
        currentScopeFingerprint: hash,
      );
      expect(result.canFinalise, isTrue);
      expect(result.categoryTotals['netCapitalGain'], '75.005');
      expect(
        result.contributions.last['kind'],
        'adviserSuppliedCompleteAnnualTotals',
      );
      expect(decision().closingLossBalances.single.amount, '10');
      expect(
        AdviserWorkpaperDecision.fromMap(decision().toMap()).totals,
        decision().totals,
      );
    },
  );
  test(
    'Prefill compares effective adviser totals while preserving other blockers',
    () {
      final accepted = applyAdviserWorkpaperDecision(
        baseReport: report(['Prefill mismatch for netCapitalGain']),
        decision: decision(covered: []),
        currentScopeFingerprint: hash,
        prefill: {'netCapitalGain': '75.005'},
      );
      expect(accepted.canFinalise, isTrue);
      final mismatch = applyAdviserWorkpaperDecision(
        baseReport: report([]),
        decision: decision(covered: []),
        currentScopeFingerprint: hash,
        prefill: {'netCapitalGain': '100'},
      );
      expect(mismatch.issues, contains('Prefill mismatch for netCapitalGain'));
      expect(mismatch.canFinalise, isFalse);
      final blocked = applyAdviserWorkpaperDecision(
        baseReport: report([
          'Required documents are missing',
          'Prefill mismatch for netCapitalGain',
        ]),
        decision: decision(covered: []),
        currentScopeFingerprint: hash,
        prefill: {'netCapitalGain': '75.005'},
      );
      expect(blocked.issues, contains('Required documents are missing'));
      expect(blocked.canFinalise, isFalse);
    },
  );
  test('Missing evidence and unreviewed source facts cannot be waived', () {
    for (final issue in [
      'salary: Source has not been reviewed',
      'Required documents are missing',
      'Invalid prior losses',
    ]) {
      final result = applyAdviserWorkpaperDecision(
        baseReport: report([issue]),
        decision: decision(covered: [issue]),
        currentScopeFingerprint: hash,
      );
      expect(result.canFinalise, isFalse);
      expect(result.issues, contains(issue));
      expect(result.categoryTotals['netCapitalGain'], '100');
    }
  });
  test('Stale scope cannot replace totals', () {
    final result = applyAdviserWorkpaperDecision(
      baseReport: report([]),
      decision: decision(source: List.filled(64, 'b').join()),
      currentScopeFingerprint: hash,
    );
    expect(result.canFinalise, isFalse);
    expect(result.categoryTotals['netCapitalGain'], '100');
  });
  test('All categories required; invalid financial values rejected', () {
    expect(decision(amounts: {'netCapitalGain': '1'}).validation(), isNotEmpty);
    expect(
      decision(amounts: {...totals, 'salaryIncome': '-1'}).validation(),
      isNotEmpty,
    );
    expect(
      decision(amounts: {...totals, 'salaryIncome': '1.001'}).validation(),
      isNotEmpty,
    );
    expect(
      decision(amounts: {...totals, 'rentalNet': '-1.01'}).validation(),
      isEmpty,
    );
  });
}
