import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/i1_adviser_decision.dart';
import 'package:simpletaxautoextraction/models/tax_workspace.dart';
import 'package:simpletaxautoextraction/models/investment_ledger.dart';
import 'package:simpletaxautoextraction/services/annual_cgt_calculator.dart';
import 'package:simpletaxautoextraction/services/tax_rule_registry.dart';
import 'annual_cgt_calculator_test.dart' show reviewed;

void main() {
  I1Review review({
    String election = 'recognise',
    String gain = '100',
    String loss = '0',
    List<String> assets = const ['asset'],
  }) => I1Review(
    date: '2025-01-01',
    assetReference: 'asset',
    classification: 'nonTAP',
    election: election,
    evidence: 'Synthetic departure',
    adviserReference: 'Synthetic adviser',
    reviewed: true,
    adviserDecision: I1AdviserDecision(
      decisionReference: 'Decision v1',
      coveredAssets: assets,
      scopeEvidence: 'Complete asset inventory checked',
      annualWorksheetReference: 'Worksheet1',
      gain: gain,
      loss: loss,
      discountFraction: '0.5',
      ruleVersion: TaxRuleRegistry.version(2024),
    ),
  );
  final ledger = InvestmentLedgerResult(
    parcels: [],
    disposals: [],
    issues: [],
    inputSnapshot: [],
  );
  test(
    'Adviser I1 gain is discounted in annual engine without actual disposal',
    () {
      final r = AnnualCgtCalculator().calculate(
        ledger: ledger,
        year: TaxYear(2024),
        context: reviewed(),
        i1Reviews: [review()],
      );
      expect(r.issues, isEmpty);
      expect(r.netCapitalGain.toString(), '50');
      expect(r.lossApplications.single['sourceKind'], 'I1-adviser');
      expect(ledger.disposals, isEmpty);
      expect(I1Review.fromMap(review().toMap()).adviserDecision!.gain, '100');
    },
  );
  test(
    'Incomplete scope and nonzero deferred event do not produce definitive total',
    () {
      for (final value in [
        review(assets: ['different']),
        review(election: 'deferAllEligible'),
      ]) {
        final r = AnnualCgtCalculator().calculate(
          ledger: ledger,
          year: TaxYear(2024),
          context: reviewed(),
          i1Reviews: [value],
        );
        expect(r.issues, isNotEmpty);
        expect(r.netCapitalGain, isNull);
      }
    },
  );
}
