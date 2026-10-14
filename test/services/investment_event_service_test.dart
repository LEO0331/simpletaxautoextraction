import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/corporate_action_decision.dart';
import 'package:simpletaxautoextraction/services/investment_event_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late InvestmentEventService service;
  CorporateActionDecision action({
    int revision = 0,
    bool voided = false,
    String date = '2024-08-01',
  }) => CorporateActionDecision(
    id: 'synthetic-split',
    userId: 'owner',
    date: date,
    parcelId: 'synthetic-buy',
    oldUnits: '10',
    newUnits: '20',
    evidenceReference: 'synthetic issuer notice',
    reviewed: true,
    revision: revision,
    isVoided: voided,
  );
  setUp(() async {
    db = FakeFirebaseFirestore();
    service = InvestmentEventService(db: db);
    await db.doc('users/owner/investment_transactions/synthetic-buy').set({
      'userId': 'owner',
      'transactionType': 'BUY',
      'isReviewed': true,
      'isVoided': false,
      'tradeDateIso': '2024-07-01',
    });
  });
  test('Persists immutable revision and advances ledger generation', () async {
    final saved = await service.saveCorporateAction(action());
    expect(saved.revision, 1);
    expect(
      (await db
              .doc('users/owner/investment_events/synthetic-split/revisions/1')
              .get())
          .data()?['newUnits'],
      '20',
    );
    expect(
      (await db.doc('users/owner/investment_metadata/ledger').get())
          .data()?['generation'],
      1,
    );
    expect((await service.getCorporateActions('owner')).single.revision, 1);
  });
  test('Stale action cannot overwrite retained revision', () async {
    await service.saveCorporateAction(action());
    await expectLater(service.saveCorporateAction(action()), throwsStateError);
    expect(
      (await db.doc('users/owner/investment_metadata/ledger').get())
          .data()?['generation'],
      1,
    );
  });
  test('Void preserves history while excluded from active replay', () async {
    await service.saveCorporateAction(action());
    await service.saveCorporateAction(action(revision: 1, voided: true));
    expect(await service.getCorporateActions('owner'), isEmpty);
    expect(
      (await service.getAllCorporateActions('owner')).single.isVoided,
      isTrue,
    );
    expect(
      (await db
              .doc('users/owner/investment_events/synthetic-split/revisions/1')
              .get())
          .data()?['isVoided'],
      false,
    );
  });
  test('Missing acquisition and same day action fail closed', () async {
    await expectLater(
      service.saveCorporateAction(action(date: '2024-07-01')),
      throwsStateError,
    );
    await db.doc('users/owner/investment_transactions/synthetic-buy').delete();
    await expectLater(service.saveCorporateAction(action()), throwsStateError);
  });
}
