import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/managed_fund_statement.dart';
import 'package:simpletaxautoextraction/services/investment_parcel_ledger.dart';
import 'investment_parcel_ledger_test.dart' show tx;

ManagedFundStatement nonAmit(String deferred, String free) =>
    ManagedFundStatement(
      id: 'fund',
      userId: 'synthetic',
      ticker: 'TEST',
      accountNumber: 'synthetic-account',
      issuer: 'Synthetic trust',
      layoutVersion: 'manual-v1',
      yearStart: 2023,
      sourceReference: 'Synthetic trustee allocation',
      regime: 'NON_AMIT',
      revision: 1,
      isReviewed: true,
      components: {
        for (final key in ManagedFundStatement.componentKeys) key: '0',
        'taxDeferred': deferred,
        'taxFree': free,
        'taxExempt': '100',
      },
      adjustments: [
        FundCostBaseAdjustment(
          parcelId: 'b',
          amount: '-$deferred',
          reducedAmount: '-${int.parse(deferred) + int.parse(free)}',
          date: '2024-06-30',
          units: '10',
          evidenceReference: 'Trustee allocation',
        ),
      ],
    );

void main() {
  test(
    'Non-AMIT tax-free affects reduced basis only; exempt affects neither',
    () {
      final statement = nonAmit('30', '35');
      expect(statement.validation(), isEmpty);
      final ledger = InvestmentParcelLedger().replay(
        transactions: [
          tx('b', DateTime.utc(2022, 1), units: '10', cash: '5000', fee: '0'),
        ],
        allocations: [],
        statements: [statement],
      );
      expect(ledger.issues, isEmpty);
      expect(ledger.parcels.single.remainingCostBase.toString(), '4970');
      expect(ledger.parcels.single.remainingReducedCostBase.toString(), '4935');
      expect(ledger.fundGains, isEmpty);
    },
  );
  test('Non-AMIT basis excess produces E4, not E10 or a disposal', () {
    final ledger = InvestmentParcelLedger().replay(
      transactions: [
        tx('b', DateTime.utc(2022, 1), units: '10', cash: '20', fee: '0'),
      ],
      allocations: [],
      statements: [nonAmit('30', '35')],
    );
    expect(ledger.issues, isEmpty);
    expect(ledger.fundGains.single.kind, 'E4');
    expect(ledger.fundGains.single.gain.toString(), '10');
    expect(ledger.parcels.single.remainingUnits.toString(), '10');
    expect(ledger.parcels.single.remainingCostBase.isZero, isTrue);
    expect(ledger.parcels.single.remainingReducedCostBase.isZero, isTrue);
    expect(ledger.disposals, isEmpty);
  });
  test('Tax-free only adjustment can have zero cost basis reduction', () {
    expect(nonAmit('0', '35').validation(), isEmpty);
  });
  test('Missing independent reduced-basis evidence cannot be reviewed', () {
    final mapped = nonAmit('30', '35').toMap();
    (mapped['adjustments'] as List).first.remove('reducedAmount');
    expect(
      ManagedFundStatement.fromMap(mapped, id: 'fund').validation(),
      isNotEmpty,
    );
  });
}
