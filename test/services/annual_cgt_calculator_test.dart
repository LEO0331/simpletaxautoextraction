import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/investment_ledger.dart';
import 'package:simpletaxautoextraction/models/tax_decimal.dart';
import 'package:simpletaxautoextraction/services/annual_cgt_calculator.dart';

RealisedDisposal disposal(
  String id, {
  required String proceeds,
  required String basis,
  DateTime? acquired,
  DateTime? sold,
}) => RealisedDisposal(
  sellTransactionId: id,
  buyTransactionId: 'buy-$id',
  acquisitionDate: acquired ?? DateTime(2023, 1, 1),
  disposalDate: sold ?? DateTime(2025, 1, 2),
  units: TaxDecimal.one,
  grossProceeds: TaxDecimal.parse(proceeds),
  disposalCosts: TaxDecimal.zero,
  costBase: TaxDecimal.parse(basis),
  reducedCostBase: TaxDecimal.parse(basis),
);
InvestmentLedgerResult ledger(List<RealisedDisposal> events) =>
    InvestmentLedgerResult(
      parcels: const [],
      disposals: events,
      issues: const [],
      inputSnapshot: const [],
    );
AnnualCgtContext reviewed({String prior = '0'}) => AnnualCgtContext(
  confirmedContinuousResident: true,
  confirmedNonTemporaryResident: true,
  completeHistory: true,
  noPendingFundAdjustments: true,
  priorLossesReviewed: true,
  confirmedSupportedAssets: true,
  priorLosses: prior,
  priorLossBalances: prior == '0'
      ? []
      : [
          CapitalLossCarryForward(
            originStartYear: 2023,
            amount: prior,
            evidenceReference: 'Synthetic reviewed loss balance',
          ),
        ],
);

void main() {
  final engine = AnnualCgtCalculator();
  test(
    'prior loss origins are consumed oldest first and retained in provenance',
    () {
      final result = engine.calculate(
        ledger: ledger([disposal('gain', proceeds: '300', basis: '100')]),
        year: TaxYear(2024),
        context: const AnnualCgtContext(
          confirmedContinuousResident: true,
          confirmedNonTemporaryResident: true,
          completeHistory: true,
          noPendingFundAdjustments: true,
          priorLossesReviewed: true,
          confirmedSupportedAssets: true,
          priorLosses: '150',
          priorLossBalances: [
            CapitalLossCarryForward(
              originStartYear: 2023,
              amount: '50',
              evidenceReference: 'Synthetic 2023 return',
            ),
            CapitalLossCarryForward(
              originStartYear: 2022,
              amount: '100',
              evidenceReference: 'Synthetic 2022 return',
            ),
          ],
        ),
      );
      expect(result.netCapitalGain.toString(), '25');
      expect(
        (result.lossApplications.single['priorLossOriginsUsed'] as List).map(
          (item) => item['originStartYear'],
        ),
        [2022, 2023],
      );
      expect(
        (result.snapshot['closingLossBalances'] as List).map(
          (item) => item['remainingAmount'],
        ),
        ['0', '0'],
      );
    },
  );
  test(
    'aggregate prior loss without origin evidence blocks definitive figures',
    () {
      final result = engine.calculate(
        ledger: ledger([]),
        year: TaxYear(2024),
        context: const AnnualCgtContext(
          confirmedContinuousResident: true,
          confirmedNonTemporaryResident: true,
          completeHistory: true,
          noPendingFundAdjustments: true,
          priorLossesReviewed: true,
          confirmedSupportedAssets: true,
          priorLosses: '100',
        ),
      );
      expect(result.netCapitalGain, isNull);
      expect(
        result.issues,
        contains(
          'Prior losses require matching originating years and evidence',
        ),
      );
    },
  );
  test('unconfirmed leap-day anniversary interpretation needs review', () {
    final result = engine.calculate(
      ledger: ledger([
        disposal(
          'leap',
          proceeds: '2',
          basis: '1',
          acquired: DateTime(2024, 2, 29),
          sold: DateTime(2025, 3, 1),
        ),
      ]),
      year: TaxYear(2024),
      context: reviewed(),
    );
    expect(result.netCapitalGain, isNull);
    expect(
      result.issues,
      contains('Leap-day anniversary boundary requires tax review'),
    );
  });
  test('financial year rejects malformed year and uses full label', () {
    expect(() => TaxYear(0), throwsArgumentError);
    expect(() => TaxYear(99999), throwsArgumentError);
    expect(TaxYear(2024).toString(), '2024-2025');
  });
  test('current then prior losses offset non-discount gains first', () {
    final result = engine.calculate(
      ledger: ledger([
        disposal('discount', proceeds: '300', basis: '100'),
        disposal(
          'short',
          proceeds: '200',
          basis: '100',
          acquired: DateTime(2024, 12),
        ),
        disposal('loss', proceeds: '50', basis: '100'),
      ]),
      year: TaxYear(2024),
      context: reviewed(prior: '100'),
    );
    expect(result.issues, isEmpty);
    expect(result.totalCapitalGains.toString(), '300');
    expect(result.currentYearLosses.toString(), '50');
    expect(result.priorLossesUsed.toString(), '100');
    expect(result.netCapitalGain.toString(), '75');
    expect(result.lossApplications.first['sellTransactionId'], 'short');
    expect(result.lossApplications.first['currentLossUsed'], '50');
    expect(result.lossApplications.first['priorLossUsed'], '50');
  });
  test('excess current and prior losses carry forward without discount', () {
    final result = engine.calculate(
      ledger: ledger([
        disposal('gain', proceeds: '110', basis: '100'),
        disposal('loss', proceeds: '10', basis: '100'),
      ]),
      year: TaxYear(2024),
      context: reviewed(prior: '20'),
    );
    expect(result.netCapitalGain.toString(), '0');
    expect(result.lossesCarriedForward.toString(), '100');
    expect(result.priorLossesUsed.toString(), '0');
  });
  test('financial-year boundaries use trade calendar dates', () {
    final result = engine.calculate(
      ledger: ledger([
        disposal(
          'june',
          proceeds: '120',
          basis: '100',
          sold: DateTime(2025, 6, 30, 23, 59),
        ),
        disposal(
          'july',
          proceeds: '140',
          basis: '100',
          sold: DateTime(2025, 7, 1),
        ),
      ]),
      year: TaxYear(2024),
      context: reviewed(),
    );
    expect(result.totalCapitalGains.toString(), '20');
    expect(result.netCapitalGain.toString(), '10');
    expect(
      result.toMap()['snapshot']['ruleVersion'],
      'AU-individual-resident-2024-2025-v1',
    );
  });
  test(
    'missing context and unsupported years produce no definitive amount',
    () {
      final result = engine.calculate(
        ledger: ledger([]),
        year: TaxYear(2026),
        context: const AnnualCgtContext(),
      );
      expect(result.status, 'NeedsTaxReview');
      expect(result.netCapitalGain, isNull);
      expect(
        result.issues,
        containsAll([
          "Unsupported financial-year rule set",
          "Residency requires tax review",
          "Acquisition and disposal history is incomplete",
          "Fund adjustments or attributed gains require reconciliation",
          "Prior capital losses, including zero, require review",
        ]),
      );
      expect(
        engine
            .calculate(
              ledger: ledger([]),
              year: TaxYear(2025),
              context: reviewed(),
            )
            .needsReview,
        isFalse,
      );
    },
  );
  test('calendar anniversary excludes acquisition and disposal days', () {
    expect(
      disposal(
        'same',
        proceeds: '2',
        basis: '1',
        acquired: DateTime(2023, 7, 1),
        sold: DateTime(2024, 7, 1),
      ).discountEligible,
      isFalse,
    );
    expect(
      disposal(
        'after',
        proceeds: '2',
        basis: '1',
        acquired: DateTime(2023, 7, 1),
        sold: DateTime(2024, 7, 2),
      ).discountEligible,
      isTrue,
    );
    expect(
      disposal(
        'leap-last',
        proceeds: '2',
        basis: '1',
        acquired: DateTime(2024, 2, 29),
        sold: DateTime(2025, 2, 28),
      ).discountEligible,
      isFalse,
    );
    expect(
      disposal(
        'leap-next',
        proceeds: '2',
        basis: '1',
        acquired: DateTime(2024, 2, 29),
        sold: DateTime(2025, 3, 1),
      ).discountEligible,
      isTrue,
    );
  });
  test('pre-indexation and invalid prior losses require review', () {
    expect(
      engine
          .calculate(
            ledger: ledger([
              disposal(
                'old',
                proceeds: '2',
                basis: '1',
                acquired: DateTime(1990),
              ),
            ]),
            year: TaxYear(2024),
            context: reviewed(),
          )
          .netCapitalGain,
      isNull,
    );
    expect(
      engine
          .calculate(
            ledger: ledger([]),
            year: TaxYear(2024),
            context: reviewed(prior: '-1'),
          )
          .netCapitalGain,
      isNull,
    );
  });
  test(
    'one cent eligible gain retains exact half cent before worksheet rounding',
    () {
      final result = engine.calculate(
        ledger: ledger([disposal('small', proceeds: '1.01', basis: '1')]),
        year: TaxYear(2024),
        context: reviewed(),
      );
      expect(result.netCapitalGain.toString(), '0.005');
    },
  );
}
