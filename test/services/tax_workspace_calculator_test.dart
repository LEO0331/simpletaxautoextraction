import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_workspace.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/models/managed_fund_statement.dart';
import 'package:simpletaxautoextraction/services/tax_workspace_calculator.dart';

void main() {
  test(
    'capital activity cannot be omitted by marking gains not applicable',
    () {
      final w = TaxWorkspace(
        userId: 'u',
        yearStart: 2024,
        sectionStates: {
          for (final s in taxWorkspaceSections) s: 'notApplicable',
        },
        sectionEvidence: {for (final s in taxWorkspaceSections) s: 'Reviewed'},
        residencyPeriods: [
          const ResidencyPeriod(
            start: '2024-07-01',
            endExclusive: '2025-07-01',
            classification: 'resident',
            evidence: 'review',
            reviewed: true,
          ),
        ],
      );
      final report = TaxWorkspaceCalculator().calculate(
        workspace: w,
        items: [],
        rentals: [],
        fundStatements: [],
        currentInvestmentGeneration: 0,
        workspaceGeneration: 0,
        hasCapitalActivity: true,
      );
      expect(report.canFinalise, false);
      expect(report.sectionIssues['capitalGains'], isNotEmpty);
    },
  );
  test(
    'ancillary deductions and offsets require their own section reconciliation',
    () {
      final w = TaxWorkspace(
        userId: 'u',
        yearStart: 2024,
        sectionStates: {
          for (final s in taxWorkspaceSections) s: 'notApplicable',
          'salary': 'reconciled',
        },
        sectionEvidence: {for (final s in taxWorkspaceSections) s: 'Reviewed'},
        residencyPeriods: [
          const ResidencyPeriod(
            start: '2024-07-01',
            endExclusive: '2025-07-01',
            classification: 'resident',
            evidence: 'review',
            reviewed: true,
          ),
        ],
      );
      final salary = TaxWorkspaceItem(
        userId: 'u',
        yearStart: 2024,
        category: 'salary',
        sourceReference: 'employer',
        amount: '100',
        deductions: '2',
        taxOffset: '3',
        isReviewed: true,
      );
      final report = TaxWorkspaceCalculator().calculate(
        workspace: w,
        items: [salary],
        rentals: [],
        fundStatements: [],
        currentInvestmentGeneration: 0,
        workspaceGeneration: 0,
      );
      expect(report.canFinalise, false);
      expect(report.sectionIssues['deductions'], isNotEmpty);
      expect(report.sectionIssues['offsets'], isNotEmpty);
      expect(report.categoryTotals['deductions'], '2');
      expect(salary.copyWith(category: 'deductions').validation(), isNotEmpty);
      expect(salary.copyWith(category: 'offsets').validation(), isNotEmpty);
    },
  );
  TaxWorkspace workspace({
    Map<String, String> states = const {},
    Map<String, String> prefill = const {},
    List<ResidencyPeriod>? periods,
    String cgt = '',
  }) => TaxWorkspace(
    userId: 'u',
    yearStart: 2024,
    cgtSnapshotId: cgt,
    sectionStates: {
      for (final s in taxWorkspaceSections) s: 'notApplicable',
      ...states,
    },
    sectionEvidence: {
      for (final s in taxWorkspaceSections)
        s: 'Complete source inventory reviewed',
    },
    prefill: prefill,
    residencyPeriods:
        periods ??
        [
          const ResidencyPeriod(
            start: '2024-07-01',
            endExclusive: '2025-07-01',
            classification: 'resident',
            evidence: 'Residency assessment',
            reviewed: true,
          ),
        ],
  );
  TaxWorkspaceReport calc(
    TaxWorkspace w, {
    List<TaxWorkspaceItem> items = const [],
    List<TaxRecord> rentals = const [],
    List<ManagedFundStatement> funds = const [],
    Map<String, dynamic>? cgt,
    int generation = 2,
    DateTime? history,
  }) => TaxWorkspaceCalculator().calculate(
    workspace: w,
    items: items,
    rentals: rentals,
    fundStatements: funds,
    cgtSnapshot: cgt,
    currentInvestmentGeneration: generation,
    workspaceGeneration: 3,
    investmentHistoryStart: history,
  );
  TaxWorkspaceItem item({
    String? id = 's',
    String category = 'salary',
    String source = 'payslip',
    String amount = '100',
    bool reviewed = true,
  }) => TaxWorkspaceItem(
    id: id,
    userId: 'u',
    yearStart: 2024,
    category: category,
    sourceReference: source,
    amount: amount,
    isReviewed: reviewed,
  );
  Map<String, dynamic> snapshot() => {
    'id': 'c',
    'userId': 'u',
    'year': '2024-2025',
    'ledgerGeneration': 2,
    'status': 'ReviewedWorksheet',
    'issues': <String>[],
    'netCapitalGain': '150',
    'snapshot': {
      'context': {
        for (final k in [
          'confirmedContinuousResident',
          'confirmedNonTemporaryResident',
          'completeHistory',
          'noPendingFundAdjustments',
          'priorLossesReviewed',
          'confirmedSupportedAssets',
        ])
          k: true,
      },
    },
  };
  test('evidenced zero-source year can be finalised without tax liability', () {
    final r = calc(workspace());
    expect(r.canFinalise, true);
    expect(r.categoryTotals.values, everyElement('0'));
    expect(r.toMap().containsKey('taxLiability'), false);
  });
  test('missing zero-source section evidence blocks finalisation', () {
    final w = workspace().copyWith(sectionEvidence: {});
    expect(calc(w).canFinalise, false);
  });
  test('source presence blocks false non-applicability', () {
    expect(calc(workspace(), items: [item()]).canFinalise, false);
  });
  test('exact salary total and prefill reconciliation', () {
    final w = workspace(
      states: {'salary': 'reconciled'},
      prefill: {'salaryIncome': '0.3'},
    );
    final r = calc(
      w,
      items: [
        item(amount: '0.1'),
        item(id: 'b', source: 'other', amount: '0.2'),
      ],
    );
    expect(r.canFinalise, true);
    expect(r.categoryTotals['salaryIncome'], '0.3');
  });
  test('prefill mismatch blocks', () {
    expect(
      calc(
        workspace(
          states: {'salary': 'reconciled'},
          prefill: {'salaryIncome': '101'},
        ),
        items: [item()],
      ).issues,
      contains('Prefill mismatch for salaryIncome'),
    );
  });
  test('duplicate source is counted once and blocks', () {
    final r = calc(
      workspace(states: {'salary': 'reconciled'}),
      items: [
        item(),
        item(id: 'duplicate'),
      ],
    );
    expect(r.categoryTotals['salaryIncome'], '100');
    expect(r.canFinalise, false);
  });
  test('unreviewed inputs do not contribute', () {
    final r = calc(
      workspace(states: {'salary': 'reconciled'}),
      items: [item(reviewed: false)],
    );
    expect(r.categoryTotals['salaryIncome'], '0');
    expect(r.canFinalise, false);
  });
  test('fractional cents rejected', () {
    expect(item(amount: '1.001').validation(), isNotEmpty);
  });
  test('rental share applied once, changed record invalidates link', () {
    final rental = TaxRecord(
      id: 'r',
      userId: 'u',
      financialYear: '2024-2025',
      income: {'Gross rent': 1000},
      expenses: {'Council rates': 100},
    );
    final link = TaxWorkspaceItem(
      id: 'link',
      userId: 'u',
      yearStart: 2024,
      category: 'rentalReview',
      sourceReference: 'agency annual',
      rentalRecordId: 'r',
      rentalFingerprint: taxRecordFingerprint(rental),
      ownershipPercent: '50',
      isReviewed: true,
    );
    final w = workspace(states: {'rental': 'reconciled'});
    final r = calc(w, items: [link], rentals: [rental]);
    expect(r.canFinalise, true);
    expect(r.categoryTotals['rentalNet'], '450');
    expect(
      calc(
        w,
        items: [link],
        rentals: [
          rental.copyWith(income: {'Gross rent': 1001}),
        ],
      ).canFinalise,
      false,
    );
  });
  test('unknown rental categories and partial cents require review', () {
    for (final income in [
      {'Unknown': 100.0},
      {'Gross rent': 1.001},
    ]) {
      final rental = TaxRecord(
        id: 'r',
        userId: 'u',
        financialYear: '2024-2025',
        income: income,
      );
      final link = TaxWorkspaceItem(
        userId: 'u',
        yearStart: 2024,
        category: 'rentalReview',
        sourceReference: 'rental',
        rentalRecordId: 'r',
        rentalFingerprint: taxRecordFingerprint(rental),
        isReviewed: true,
      );
      expect(
        calc(
          workspace(states: {'rental': 'reconciled'}),
          items: [link],
          rentals: [rental],
        ).canFinalise,
        false,
      );
    }
  });
  test('resident timeline gaps overlaps and temporary periods block', () {
    for (final periods in [
      [
        const ResidencyPeriod(
          start: '2024-07-02',
          endExclusive: '2025-07-01',
          classification: 'resident',
          evidence: 'assessed',
          reviewed: true,
        ),
      ],
      [
        const ResidencyPeriod(
          start: '2024-07-01',
          endExclusive: '2025-01-01',
          classification: 'resident',
          evidence: 'assessed',
          reviewed: true,
        ),
        const ResidencyPeriod(
          start: '2024-12-01',
          endExclusive: '2025-07-01',
          classification: 'resident',
          evidence: 'assessed',
          reviewed: true,
        ),
      ],
      [
        const ResidencyPeriod(
          start: '2024-07-01',
          endExclusive: '2025-07-01',
          classification: 'temporary',
          evidence: 'assessed',
          reviewed: true,
        ),
      ],
    ]) {
      expect(calc(workspace(periods: periods)).canFinalise, false);
    }
  });
  test('CGT reviewed snapshot and historical resident coverage required', () {
    final w = workspace(states: {'capitalGains': 'reconciled'}, cgt: 'c');
    expect(
      calc(w, cgt: snapshot(), history: DateTime.utc(2024, 7)).canFinalise,
      true,
    );
    expect(
      calc(w, cgt: snapshot(), history: DateTime.utc(2020)).canFinalise,
      false,
    );
    expect(
      calc(
        w,
        cgt: snapshot(),
        history: DateTime.utc(2024, 7),
        generation: 3,
      ).canFinalise,
      false,
    );
  });
  test('fund capital gains included only through annual CGT snapshot', () {
    final components = {
      for (final k in ManagedFundStatement.componentKeys) k: '0',
      'australianIncome': '10',
      'foreignIncome': '5',
      'discountedCapitalGain': '100',
      'grossCapitalGain': '200',
    };
    final fund = ManagedFundStatement(
      id: 'f',
      userId: 'u',
      ticker: 'ETF',
      accountNumber: 'account',
      issuer: 'Issuer',
      layoutVersion: 'v1',
      yearStart: 2024,
      sourceReference: 'annual',
      isReviewed: true,
      components: components,
    );
    final r = calc(
      workspace(
        states: {'funds': 'reconciled', 'capitalGains': 'reconciled'},
        cgt: 'c',
      ),
      funds: [fund],
      cgt: snapshot(),
      history: DateTime.utc(2024, 7),
    );
    expect(r.canFinalise, true);
    expect(r.categoryTotals['netCapitalGain'], '150');
    expect(r.categoryTotals['fundAustralianIncome'], '10');
    expect(r.categoryTotals['fundForeignIncome'], '5');
  });
  test('I1 mixed elections blocked, scenarios excluded from annual totals', () {
    final w = workspace().copyWith(
      i1Reviews: [
        const I1Review(
          date: '2025-01-01',
          assetReference: 'a',
          marketValue: '100',
          costBase: '50',
          reducedCostBase: '50',
          classification: 'nonTAP',
          election: 'recognise',
          evidence: 'valuation',
          adviserReference: 'assessment',
          reviewed: true,
        ),
        const I1Review(
          date: '2025-01-01',
          assetReference: 'b',
          marketValue: '100',
          costBase: '150',
          reducedCostBase: '150',
          classification: 'nonTAP',
          election: 'deferAllEligible',
          evidence: 'valuation',
          adviserReference: 'assessment',
          reviewed: true,
        ),
      ],
    );
    final r = calc(w);
    expect(r.canFinalise, false);
    expect(r.i1Scenarios.first['undiscountedGain'], '50');
    expect(r.categoryTotals['netCapitalGain'], '0');
    expect(r.issues.any((p) => p.contains('mixed choices')), true);
  });
  test('fingerprint canonical order lifecycle and dependencies', () {
    final w = workspace();
    final first = calc(w);
    expect(
      calc(
        w.copyWith(status: 'finalised', revision: 1, amendmentReason: 'reason'),
      ).sourceFingerprint,
      first.sourceFingerprint,
    );
    expect(
      calc(w, generation: 3).sourceFingerprint,
      isNot(first.sourceFingerprint),
    );
    expect(
      canonicalTaxFingerprint({'b': 2, 'a': 1}),
      canonicalTaxFingerprint({'a': 1, 'b': 2}),
    );
    expect(
      () => first.categoryTotals['salaryIncome'] = '9',
      throwsUnsupportedError,
    );
  });
  test('models round trip versioned facts', () {
    final w = workspace();
    expect(TaxWorkspace.fromMap(w.toMap()).toMap(), w.toMap());
    final i = item();
    expect(TaxWorkspaceItem.fromMap(i.toMap(), id: i.id).toMap(), i.toMap());
    expect(
      () => TaxWorkspace.fromMap({...w.toMap(), 'schemaVersion': 2}),
      throwsFormatException,
    );
  });
}
