import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/corporate_action_decision.dart';
import 'package:simpletaxautoextraction/services/investment_parcel_ledger.dart';
import 'investment_parcel_ledger_test.dart' show tx, allocation;

void main() {
  CorporateActionDecision action({
    String old = '10',
    String units = '20',
    String date = '2023-01-01',
  }) => CorporateActionDecision(
    id: 'split',
    userId: 'synthetic',
    date: date,
    parcelId: 'b',
    oldUnits: old,
    newUnits: units,
    evidenceReference: 'Synthetic issuer split',
    reviewed: true,
    revision: 1,
  );
  final buy = tx(
    'b',
    DateTime.utc(2022, 1),
    units: '10',
    cash: '1000',
    fee: '0',
  );
  test('Split conserves both bases and original acquisition date', () {
    final result = InvestmentParcelLedger().replay(
      transactions: [buy],
      allocations: [],
      corporateActions: [action()],
    );
    expect(result.issues, isEmpty);
    expect(result.parcels.single.remainingUnits.toString(), '20');
    expect(result.parcels.single.remainingCostBase.toString(), '1000');
    expect(result.parcels.single.remainingReducedCostBase.toString(), '1000');
    expect(result.parcels.single.acquisitionDate, DateTime.utc(2022, 1));
    expect(result.toMap()['corporateActionRevisions'], {'split': 1});
    expect(result.disposals, isEmpty);
  });
  test(
    'Partial disposal after split uses transformed units and conserved basis',
    () {
      final sale = tx(
        's',
        DateTime.utc(2024, 1),
        sell: true,
        units: '10',
        cash: '1000',
        fee: '0',
      );
      final result = InvestmentParcelLedger().replay(
        transactions: [buy, sale],
        allocations: [
          allocation('s', {'b': '10'}),
        ],
        corporateActions: [action()],
      );
      expect(result.issues, isEmpty);
      expect(result.disposals.single.capitalGain.toString(), '500');
      expect(result.parcels.single.remainingCostBase.toString(), '500');
    },
  );
  test(
    'Mismatched holdings or ambiguous acquisition-day split cannot change basis',
    () {
      for (final a in [action(old: '11'), action(date: '2022-01-01')]) {
        final result = InvestmentParcelLedger().replay(
          transactions: [buy],
          allocations: [],
          corporateActions: [a],
        );
        expect(result.issues, isNotEmpty);
        expect(result.parcels.single.remainingUnits.toString(), '10');
      }
    },
  );
}
