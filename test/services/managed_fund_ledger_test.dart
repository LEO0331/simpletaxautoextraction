import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/managed_fund_statement.dart';
import 'package:simpletaxautoextraction/models/investment_ledger.dart';
import 'package:simpletaxautoextraction/services/investment_parcel_ledger.dart';
import 'package:simpletaxautoextraction/services/annual_cgt_calculator.dart';
import 'investment_parcel_ledger_test.dart' show tx, allocation;
import 'annual_cgt_calculator_test.dart' show reviewed;

ManagedFundStatement statement({
  String id = 'fund',
  int year = 2023,
  String amount = '300',
  String? sale,
  String units = '10',
  String? date,
  List<FundDrpLink> drp = const [],
  Map<String, String> extra = const {},
  bool isReviewed = true,
  String regime = 'AMIT',
  int revision = 1,
}) => ManagedFundStatement(
  id: id,
  userId: 'synthetic',
  ticker: 'TEST',
  accountNumber: 'synthetic-account',
  issuer: 'Synthetic fund',
  layoutVersion: 'manual-v1',
  yearStart: year,
  sourceReference: 'synthetic-source',
  isReviewed: isReviewed,
  regime: regime,
  revision: revision,
  components: {
    for (final k in ManagedFundStatement.componentKeys) k: '0',
    if (!amount.startsWith('-')) 'amitShortfall': amount,
    if (amount.startsWith('-')) 'amitExcess': amount.substring(1),
    ...extra,
  },
  adjustments: amount == '0'
      ? []
      : [
          FundCostBaseAdjustment(
            parcelId: 'b',
            amount: amount,
            date: date ?? '${year + 1}-06-30',
            beforeSaleId: sale,
            units: units,
            evidenceReference: 'Evidenced units allocation',
          ),
        ],
  drpLinks: drp,
);

void main() {
  test('Zero annual net adjustment cannot hide offsetting parcel changes', () {
    final source = statement(amount: '0');
    final mapped = source.toMap();
    mapped['adjustments'] = [
      const FundCostBaseAdjustment(
        parcelId: 'b',
        amount: '100',
        date: '2024-06-30',
        units: '10',
        evidenceReference: 'Synthetic allocation',
      ).toMap(),
      const FundCostBaseAdjustment(
        parcelId: 'other',
        amount: '-100',
        date: '2024-06-30',
        units: '10',
        evidenceReference: 'Synthetic allocation',
      ).toMap(),
    ];
    expect(
      ManagedFundStatement.fromMap(mapped, id: 'fund').validation(),
      contains(
        'A zero AMIT net amount cannot contain offsetting adjustment slices',
      ),
    );
  });
  final engine = InvestmentParcelLedger();
  final buy = tx(
    'b',
    DateTime.utc(2022, 1),
    units: '10',
    cash: '10000',
    fee: '0',
  );
  final sale = tx(
    's',
    DateTime.utc(2025, 1),
    sell: true,
    units: '10',
    cash: '11000',
    fee: '0',
  );
  for (final entry in {'300': '700', '-300': '1300'}.entries) {
    test('Historical adjustment ${entry.key} gives gain ${entry.value}', () {
      final result = engine.replay(
        transactions: [buy, sale],
        allocations: [
          allocation('s', {'b': '10'}),
        ],
        statements: [statement(amount: entry.key)],
      );
      expect(result.issues, isEmpty);
      expect(result.disposals.single.capitalGain.toString(), entry.value);
      expect(result.costBaseHistory.single['amount'], entry.key);
      expect(result.toMap()['statementRevisions'], {'fund': 1});
    });
  }
  test('Repeated years apply chronologically despite source ordering', () {
    final r = engine.replay(
      transactions: [buy, sale],
      allocations: [
        allocation('s', {'b': '10'}),
      ],
      statements: [
        statement(
          id: 'later',
          year: 2024,
          amount: '200',
          sale: 's',
          date: '2025-01-01',
        ),
        statement(),
      ],
    );
    expect(r.issues, isEmpty);
    expect(r.disposals.single.capitalGain.toString(), '500');
  });
  test('Pre-disposal adjustment changes only the sold interest', () {
    final partial = tx(
      's',
      DateTime.utc(2025, 1),
      sell: true,
      units: '4',
      cash: '4400',
      fee: '0',
    );
    final r = engine.replay(
      transactions: [buy, partial],
      allocations: [
        allocation('s', {'b': '4'}),
      ],
      statements: [
        statement(
          year: 2024,
          amount: '120',
          sale: 's',
          units: '4',
          date: '2025-01-01',
        ),
      ],
    );
    expect(r.issues, isEmpty);
    expect(r.disposals.single.capitalGain.toString(), '280');
    expect(r.parcels.single.remainingCostBase.toString(), '6000');
  });
  test(
    'Year-end adjustment after a partial sale applies only retained units',
    () {
      final partial = tx(
        's',
        DateTime.utc(2024, 1),
        sell: true,
        units: '4',
        cash: '4400',
        fee: '0',
      );
      final r = engine.replay(
        transactions: [buy, partial],
        allocations: [
          allocation('s', {'b': '4'}),
        ],
        statements: [statement(units: '6')],
      );
      expect(r.issues, isEmpty);
      expect(r.disposals.single.capitalGain.toString(), '400');
      expect(r.parcels.single.remainingCostBase.toString(), '6300');
    },
  );
  test('Disposed interest cannot receive later year-end adjustment', () {
    final r = engine.replay(
      transactions: [
        buy,
        tx(
          's',
          DateTime.utc(2024, 1),
          sell: true,
          units: '10',
          cash: '11000',
          fee: '0',
        ),
      ],
      allocations: [
        allocation('s', {'b': '10'}),
      ],
      statements: [statement()],
    );
    expect(r.needsReview, isTrue);
    expect(r.costBaseHistory, isEmpty);
  });
  test('Excess floors both bases and creates only surplus E10 gain', () {
    final r = engine.replay(
      transactions: [buy],
      allocations: [],
      statements: [statement(year: 2024, amount: '-10300')],
    );
    expect(r.issues, isEmpty);
    expect(r.parcels.single.remainingCostBase.toString(), '0');
    expect(r.parcels.single.remainingReducedCostBase.toString(), '0');
    expect(r.fundGains.single.gain.toString(), '300');
    final annual = AnnualCgtCalculator().calculate(
      ledger: r,
      year: TaxYear(2024),
      context: reviewed(),
    );
    expect(annual.issues, isEmpty);
    expect(annual.totalCapitalGains.toString(), '300');
    expect(annual.netCapitalGain.toString(), '150');
  });
  test('DRP reconciles existing BUY without creating a second parcel', () {
    final drp = tx(
      'd',
      DateTime.utc(2024, 8),
      units: '1',
      cash: '200',
      fee: '0',
    );
    final s = statement(
      year: 2024,
      amount: '0',
      extra: {'cashDistributions': '210'},
      drp: [
        const FundDrpLink(
          buyTransactionId: 'd',
          cashEntitlement: '210',
          reinvestedAmount: '200',
          residualCash: '10',
          evidenceReference: 'DRP advice',
        ),
      ],
    );
    final r = engine.replay(
      transactions: [buy, drp],
      allocations: [],
      statements: [s],
    );
    expect(r.issues, isEmpty);
    expect(r.parcels.length, 2);
    expect(
      engine
          .replay(transactions: [buy], allocations: [], statements: [s])
          .needsReview,
      isTrue,
    );
  });
  test(
    'Duplicate statements and unsupported/unreviewed statements require review',
    () {
      expect(
        engine
            .replay(
              transactions: [buy],
              allocations: [],
              statements: [
                statement(),
                statement(id: 'duplicate'),
              ],
            )
            .needsReview,
        isTrue,
      );
      expect(
        engine
            .replay(
              transactions: [buy],
              allocations: [],
              statements: [statement(isReviewed: false)],
            )
            .needsReview,
        isTrue,
      );
      expect(
        statement(regime: 'non-AMIT', amount: '0').validation(),
        isNotEmpty,
      );
    },
  );
  test('Corrected statement replaces earlier effects and records revision', () {
    final r = engine.replay(
      transactions: [buy, sale],
      allocations: [
        allocation('s', {'b': '10'}),
      ],
      statements: [statement(amount: '200', revision: 2)],
    );
    expect(r.issues, isEmpty);
    expect(r.disposals.single.capitalGain.toString(), '800');
    expect(r.toMap()['statementRevisions'], {'fund': 2});
  });
  test(
    'Fund discounted gain is grossed once and combines losses before discount',
    () {
      final lossSale = tx(
        's',
        DateTime.utc(2025, 1),
        sell: true,
        units: '10',
        cash: '9800',
        fee: '0',
      );
      final r = engine.replay(
        transactions: [buy, lossSale],
        allocations: [
          allocation('s', {'b': '10'}),
        ],
        statements: [
          statement(
            year: 2024,
            amount: '0',
            extra: {
              'discountedCapitalGain': '500',
              'otherCapitalGain': '100',
              'grossCapitalGain': '1100',
            },
          ),
        ],
      );
      expect(r.issues, isEmpty);
      final a = AnnualCgtCalculator().calculate(
        ledger: r,
        year: TaxYear(2024),
        context: reviewed(),
      );
      expect(a.issues, isEmpty);
      expect(a.totalCapitalGains.toString(), '1100');
      expect(a.currentYearLosses.toString(), '200');
      expect(a.netCapitalGain.toString(), '450');
    },
  );
  test('Snapshot provenance is immutable and model round-trips', () {
    final s = statement();
    expect(
      ManagedFundStatement.fromMap(s.toMap(), id: s.id).validation(),
      isEmpty,
    );
    final r = engine.replay(
      transactions: [buy],
      allocations: [],
      statements: [s],
    );
    expect(
      () => r.statementsSnapshot.single['revision'] = 99,
      throwsUnsupportedError,
    );
  });
  test('Future-year statements are excluded from historical cutoff', () {
    final r = engine.replay(
      transactions: [buy],
      allocations: [],
      asOfDate: DateTime.utc(2024, 6, 30),
      statements: [statement(year: 2025, isReviewed: false)],
    );
    expect(r.issues, isEmpty);
    expect(r.statementsSnapshot, isEmpty);
  });
  test(
    'Missing component zeros and conflicting allocation signs are rejected',
    () {
      final s = statement();
      final map = s.toMap();
      (map['components'] as Map).remove('withholding');
      expect(
        ManagedFundStatement.fromMap(map, id: s.id).validation(),
        isNotEmpty,
      );
      map['components'] = s.components;
      map['adjustments'] = [
        const FundCostBaseAdjustment(
          parcelId: 'b',
          amount: '400',
          date: '2024-06-30',
          units: '10',
          evidenceReference: 'a',
        ).toMap(),
        const FundCostBaseAdjustment(
          parcelId: 'other',
          amount: '-100',
          date: '2024-06-30',
          units: '1',
          evidenceReference: 'b',
        ).toMap(),
      ];
      expect(
        ManagedFundStatement.fromMap(map, id: s.id).validation(),
        isNotEmpty,
      );
    },
  );
  test('Invalid sale commits neither adjustment history nor E10 gain', () {
    final sale = tx(
      's',
      DateTime.utc(2025, 1),
      sell: true,
      units: '11',
      cash: '12000',
      fee: '0',
    );
    final r = engine.replay(
      transactions: [buy, sale],
      allocations: [
        allocation('s', {'b': '11'}),
      ],
      statements: [
        statement(
          year: 2024,
          amount: '-10300',
          sale: 's',
          units: '11',
          date: '2025-01-01',
        ),
      ],
    );
    expect(r.needsReview, isTrue);
    expect(r.costBaseHistory, isEmpty);
    expect(r.fundGains, isEmpty);
    expect(r.parcels.single.remainingCostBase.toString(), '10000');
  });
  test(
    'Adjustment on sale date is excluded before cutoff and committed on cutoff',
    () {
      final s = statement(year: 2024, sale: 's', date: '2025-01-01');
      final before = engine.replay(
        transactions: [buy, sale],
        allocations: [
          allocation('s', {'b': '10'}),
        ],
        statements: [s],
        asOfDate: DateTime.utc(2024, 12, 31),
      );
      expect(before.issues, isEmpty);
      expect(before.costBaseHistory, isEmpty);
      expect(before.parcels.single.remainingCostBase.toString(), '10000');
      final on = engine.replay(
        transactions: [buy, sale],
        allocations: [
          allocation('s', {'b': '10'}),
        ],
        statements: [s],
        asOfDate: DateTime.utc(2025, 1, 1),
      );
      expect(on.issues, isEmpty);
      expect(on.disposals.single.capitalGain.toString(), '700');
    },
  );
  test('Year-end adjustment occurs after a sale on June 30', () {
    final juneSale = tx(
      's',
      DateTime.utc(2024, 6, 30),
      sell: true,
      units: '4',
      cash: '4400',
      fee: '0',
    );
    final r = engine.replay(
      transactions: [buy, juneSale],
      allocations: [
        allocation('s', {'b': '4'}),
      ],
      statements: [statement(units: '6')],
      asOfDate: DateTime.utc(2024, 6, 30),
    );
    expect(r.issues, isEmpty);
    expect(r.disposals.single.capitalGain.toString(), '400');
    expect(r.parcels.single.remainingCostBase.toString(), '6300');
  });
  test(
    'Pre-disposal adjustment with missing sale selection cannot disappear silently',
    () {
      final s = statement(year: 2024, sale: 'missing-sale', date: '2025-01-01');
      expect(
        engine
            .replay(transactions: [buy], allocations: [], statements: [s])
            .needsReview,
        isTrue,
      );
    },
  );
}
