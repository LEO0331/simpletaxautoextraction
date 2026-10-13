import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/investment_transaction.dart';
import 'package:simpletaxautoextraction/services/investment_draft_sync_service.dart';

void main() {
  InvestmentTransaction transaction() => InvestmentTransaction(
    userId: 'u',
    ticker: 'EXM',
    securityName: 'Example',
    transactionType: InvestmentTransactionType.buy,
    tradeDate: DateTime(2026, 3, 30),
    units: 10,
    averagePrice: 100,
    consideration: 1000,
    brokerage: 2.5,
    totalCost: 1002.5,
    sourceParser: 'manual',
    parserVersion: 'v1',
  );
  test('legacy documents remain unreviewed without exact evidence', () {
    final result = InvestmentTransaction.fromMap({
      'tradeDate': Timestamp.fromDate(DateTime(2026, 3, 30)),
      'units': 10,
    }, 'legacy');
    expect(result.isReviewed, isFalse);
    expect(result.unitsExact, isNull);
    expect(result.revision, 0);
  });
  test('v2 evidence survives persistence and copying', () {
    final original = transaction().copyWith(
      unitsExact: '10.0000',
      considerationExact: '1000.00',
      brokerageExact: '2.50',
      totalCostExact: '1002.50',
      sourceHash: 'test-source',
      isReviewed: true,
      revision: 4,
    );
    final map = original.toMap();
    expect(map['schemaVersion'], 2);
    final result = InvestmentTransaction.fromMap(
      map,
      'id',
    ).copyWith(notes: 'checked');
    expect(result.unitsExact, '10.0000');
    expect(result.totalCostExact, '1002.50');
    expect(result.sourceHash, 'test-source');
    expect(result.isReviewed, isTrue);
    expect(result.revision, 4);
  });
  test('void state survives persistence and copying', () {
    final map = transaction().copyWith(isVoided: true).toMap();
    final restored = InvestmentTransaction.fromMap(
      map,
      'id',
    ).copyWith(notes: 'audit');
    expect(restored.isVoided, isTrue);
    expect(restored.copyWith(isVoided: false).isVoided, isFalse);
  });
  test(
    'date-only trades round trip without client timezone shifting the day',
    () {
      final original = transaction().copyWith(
        tradeDate: DateTime(2026, 6, 30),
        unitsExact: '10',
        considerationExact: '1000',
        brokerageExact: '2.50',
        totalCostExact: '1002.50',
        isReviewed: true,
      );
      final data = original.toMap();
      expect(data['tradeDateIso'], '2026-06-30');
      final restored = InvestmentTransaction.fromMap(data, 'date-test');
      expect(restored.tradeDate, DateTime.utc(2026, 6, 30));
      expect(restored.isReviewed, isTrue);
      expect(
        InvestmentTransaction.fromMap({
          ...data,
          'tradeDateIso': '2026-02-30',
        }, 'bad-date').isReviewed,
        isFalse,
      );
    },
  );
  test(
    'review flag requires supported schema direction and exact evidence',
    () {
      final map = transaction()
          .copyWith(
            isReviewed: true,
            unitsExact: '10',
            considerationExact: '1000.00',
            brokerageExact: '2.50',
            totalCostExact: '1002.50',
          )
          .toMap();
      expect(InvestmentTransaction.fromMap(map, 'id').isReviewed, isTrue);
      for (final invalid in [
        {...map, 'transactionType': 'UNKNOWN'},
        {...map, 'schemaVersion': 1},
        {...map, 'schemaVersion': 3},
        {...map, 'unitsExact': null},
        {...map, 'brokerageExact': ''},
      ]) {
        expect(
          InvestmentTransaction.fromMap(invalid, 'id').isReviewed,
          isFalse,
        );
      }
    },
  );
  test('draft queue keeps separate accounts and confirmations', () {
    final service = InvestmentDraftSyncService.instance;
    service.clearPendingDrafts();
    addTearDown(service.clearPendingDrafts);
    final first = transaction().copyWith(
      accountNumber: 'account-a',
      confirmationNumber: 'confirmation-a',
    );
    service.queueDraft(first);
    service.queueDraft(first.copyWith(notes: 'replacement'));
    service.queueDraft(first.copyWith(accountNumber: 'account-b'));
    service.queueDraft(first.copyWith(confirmationNumber: 'confirmation-b'));
    expect(service.pendingDrafts.length, 3);
    expect(service.pendingDrafts.first.notes, 'replacement');
  });
}
