import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/investment_transaction.dart';
import 'package:simpletaxautoextraction/models/investment_ledger.dart';
import 'package:simpletaxautoextraction/models/tax_decimal.dart';
import 'package:simpletaxautoextraction/services/investment_parcel_ledger.dart';

InvestmentTransaction tx(
  String id,
  DateTime date, {
  bool sell = false,
  String units = '3',
  String cash = '100',
  String fee = '1',
  String? total,
}) {
  final totalValue =
      total ??
      (sell
              ? TaxDecimal.parse(cash) - TaxDecimal.parse(fee)
              : TaxDecimal.parse(cash) + TaxDecimal.parse(fee))
          .toString();
  return InvestmentTransaction(
    id: id,
    userId: 'synthetic',
    ticker: 'TEST',
    securityName: 'Synthetic share',
    transactionType: sell
        ? InvestmentTransactionType.sell
        : InvestmentTransactionType.buy,
    tradeDate: date,
    units: double.parse(units),
    averagePrice: 0,
    consideration: double.parse(cash),
    brokerage: double.parse(fee),
    totalCost: double.parse(totalValue),
    accountNumber: 'synthetic-account',
    confirmationNumber: 'synthetic-$id',
    sourceParser: 'synthetic',
    parserVersion: 'v1',
    unitsExact: units,
    considerationExact: cash,
    brokerageExact: fee,
    totalCostExact: totalValue,
    isReviewed: true,
  );
}

SaleAllocation allocation(String sell, Map<String, String> selections) =>
    SaleAllocation(
      sellTransactionId: sell,
      selections: selections.entries
          .map((e) => ParcelSelection(buyTransactionId: e.key, units: e.value))
          .toList(),
      transactionRevisions: {sell: 0, for (final id in selections.keys) id: 0},
    );

void main() {
  final engine = InvestmentParcelLedger();
  test('blank and mixed user identities reject replay', () {
    final buy = tx('b', DateTime(2023));
    expect(
      engine
          .replay(
            transactions: [buy.copyWith(userId: '')],
            allocations: [],
          )
          .needsReview,
      isTrue,
    );
    final mixed = engine.replay(
      transactions: [
        buy,
        tx('s', DateTime(2025), sell: true).copyWith(userId: 'other'),
      ],
      allocations: [
        allocation('s', {'b': '3'}),
      ],
    );
    expect(mixed.parcels, isEmpty);
    expect(mixed.disposals, isEmpty);
    expect(mixed.needsReview, isTrue);
  });
  test('SELL net total mismatch and negative net proceeds consume nothing', () {
    for (final sale in [
      tx('s', DateTime(2025), sell: true, total: '100'),
      tx('s', DateTime(2025), sell: true, cash: '1', fee: '2', total: '0'),
    ]) {
      final result = engine.replay(
        transactions: [tx('b', DateTime(2023)), sale],
        allocations: [
          allocation('s', {'b': '3'}),
        ],
      );
      expect(result.needsReview, isTrue);
      expect(result.disposals, isEmpty);
      expect(result.parcels.single.remainingUnits.toString(), '3');
    }
  });
  test('calculation input snapshot is detached and recursively immutable', () {
    final selected = allocation('s', {'b': '3'});
    final result = engine.replay(
      transactions: [
        tx('b', DateTime(2023)),
        tx('s', DateTime(2025), sell: true),
      ],
      allocations: [selected],
    );
    selected.transactionRevisions['b'] = 99;
    final frozen = result.inputSnapshot.last['allocation'] as Map;
    expect((frozen['transactionRevisions'] as Map)['b'], 0);
    expect(
      () => (frozen['transactionRevisions'] as Map)['b'] = 1,
      throwsUnsupportedError,
    );
    expect(
      () => result.inputSnapshot.last['revision'] = 5,
      throwsUnsupportedError,
    );
  });
  test('partial then final disposal conserves basis and fees once', () {
    final result = engine.replay(
      transactions: [
        tx('b', DateTime(2023)),
        tx(
          's1',
          DateTime(2024, 8),
          sell: true,
          units: '1',
          cash: '50',
          fee: '2',
          total: '48',
        ),
        tx(
          's2',
          DateTime(2025, 1),
          sell: true,
          units: '2',
          cash: '120',
          fee: '3',
          total: '117',
        ),
      ],
      allocations: [
        allocation('s1', {'b': '1'}),
        allocation('s2', {'b': '2'}),
      ],
    );
    expect(result.issues, isEmpty);
    expect(result.parcels.single.remainingUnits.toString(), '0');
    expect(result.parcels.single.remainingCostBase.toString(), '0');
    expect(result.disposals.map((d) => d.costBase.toString()), [
      '33.67',
      '67.33',
    ]);
    expect(result.disposals.map((d) => d.netProceeds.toString()), [
      '48',
      '117',
    ]);
    expect(result.toMap()['inputRevisions'], {'b': 0, 's1': 0, 's2': 0});
    expect(result.toMap()['allocationRevisions'], {'s1': 0, 's2': 0});
  });
  test('multi-parcel residual cents never produce negative proceeds', () {
    final result = engine.replay(
      transactions: [
        for (var i = 0; i < 4; i++)
          tx(
            'b$i',
            DateTime(2023, 1, i + 1),
            units: '1',
            cash: '1',
            fee: '0',
            total: '1',
          ),
        tx(
          's',
          DateTime(2025),
          sell: true,
          units: '4',
          cash: '0.02',
          fee: '0.01',
          total: '0.01',
        ),
      ],
      allocations: [
        allocation('s', {for (var i = 0; i < 4; i++) 'b$i': '1'}),
      ],
    );
    expect(result.issues, isEmpty);
    expect(
      result.disposals.every(
        (d) => !d.grossProceeds.isNegative && !d.disposalCosts.isNegative,
      ),
      isTrue,
    );
    expect(
      result.disposals
          .map((d) => double.parse(d.grossProceeds.toString()))
          .reduce((a, b) => a + b),
      0.02,
    );
  });
  test('oversell is atomic and blocks worksheet', () {
    final result = engine.replay(
      transactions: [
        tx('b', DateTime(2023)),
        tx('s', DateTime(2025), sell: true, units: '4'),
      ],
      allocations: [
        allocation('s', {'b': '4'}),
      ],
    );
    expect(result.needsReview, isTrue);
    expect(result.disposals, isEmpty);
    expect(result.parcels.single.remainingUnits.toString(), '3');
  });
  test('no implicit FIFO, stale revisions, and repeated selections', () {
    final facts = [
      tx('b', DateTime(2023)),
      tx('s', DateTime(2025), sell: true),
    ];
    expect(
      engine.replay(transactions: facts, allocations: []).needsReview,
      isTrue,
    );
    expect(
      engine
          .replay(
            transactions: [facts.first.copyWith(revision: 1), facts.last],
            allocations: [
              allocation('s', {'b': '3'}),
            ],
          )
          .needsReview,
      isTrue,
    );
    expect(
      engine
          .replay(
            transactions: facts,
            allocations: [
              SaleAllocation(
                sellTransactionId: 's',
                selections: const [
                  ParcelSelection(buyTransactionId: 'b', units: '1'),
                  ParcelSelection(buyTransactionId: 'b', units: '2'),
                ],
                transactionRevisions: const {'s': 0, 'b': 0},
              ),
            ],
          )
          .disposals,
      isEmpty,
    );
  });
  test('same-day purchase and sale require ordering evidence', () {
    final facts = [
      tx('b', DateTime(2025, 1, 1, 9)),
      tx('s', DateTime(2025, 1, 1, 15), sell: true),
    ];
    final a = engine.replay(
      transactions: facts,
      allocations: [
        allocation('s', {'b': '3'}),
      ],
    );
    final b = engine.replay(
      transactions: facts.reversed.toList(),
      allocations: [
        allocation('s', {'b': '3'}),
      ],
    );
    expect(a.issues, b.issues);
    expect(a.disposals, isEmpty);
  });
  test('unreviewed, missing exact, and mismatched buy total block replay', () {
    expect(
      engine
          .replay(
            transactions: [tx('b', DateTime(2023)).copyWith(isReviewed: false)],
            allocations: [],
          )
          .needsReview,
      isTrue,
    );
    expect(
      engine
          .replay(
            transactions: [tx('b', DateTime(2023), total: '100')],
            allocations: [],
          )
          .needsReview,
      isTrue,
    );
  });
  test('cutoff excludes future sale without requiring its allocation', () {
    final result = engine.replay(
      transactions: [
        tx('b', DateTime(2023)),
        tx('s', DateTime(2026), sell: true),
      ],
      allocations: [],
      asOfDate: DateTime(2025, 6, 30),
    );
    expect(result.issues, isEmpty);
    expect(result.parcels.single.remainingUnits.toString(), '3');
  });
  test('allocation serialization preserves exact units and revision', () {
    final source = SaleAllocation(
      sellTransactionId: 's',
      selections: const [
        ParcelSelection(buyTransactionId: 'b', units: '0.123456789'),
      ],
      transactionRevisions: const {'b': 4, 's': 2},
      revision: 3,
    );
    expect(SaleAllocation.fromMap(source.toMap()).toMap(), source.toMap());
  });
}
