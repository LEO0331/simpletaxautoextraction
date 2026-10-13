import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/managed_fund_statement.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';

ManagedFundStatement statement({
  String? id,
  int revision = 0,
  bool voided = false,
  Map<String, String> components = const {},
  String source = 'Synthetic annual statement',
}) => ManagedFundStatement(
  id: id,
  userId: 'owner',
  ticker: 'SYN',
  accountNumber: 'synthetic-account',
  issuer: 'Synthetic issuer',
  layoutVersion: 'annual-v1',
  yearStart: 2024,
  sourceReference: source,
  revision: revision,
  isReviewed: true,
  isVoided: voided,
  components: {
    for (final key in ManagedFundStatement.componentKeys) key: '0',
    ...components,
  },
);

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreService service;
  setUp(() {
    db = FakeFirebaseFirestore();
    service = FirestoreService(db: db);
  });
  test('reimport is idempotent without advancing ledger generation', () async {
    final first = await service.saveManagedFundStatement(statement());
    final second = await service.saveManagedFundStatement(statement());
    expect(first, second);
    expect(await service.getInvestmentLedgerGeneration('owner'), 1);
    expect(
      (await service.getManagedFundStatementsOnce('owner')).single.revision,
      1,
    );
    expect(await service.getManagedFundStatementsOnce('other'), isEmpty);
  });
  test(
    'correction keeps immutable old facts and rejects a stale revision',
    () async {
      final id = await service.saveManagedFundStatement(statement());
      await service.saveManagedFundStatement(
        statement(
          id: id,
          revision: 1,
          components: {'australianIncome': '50'},
          source: 'Synthetic correction',
        ),
      );
      final history = await service.getManagedFundStatementRevisionsOnce(
        'owner',
        id,
      );
      expect(history.map((r) => r['revision']), [2, 1]);
      expect((history.last['components'] as Map)['australianIncome'], '0');
      expect(await service.getInvestmentLedgerGeneration('owner'), 2);
      await expectLater(
        service.saveManagedFundStatement(
          statement(
            id: id,
            revision: 1,
            components: {'australianIncome': '100'},
          ),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'void preserves history and removes current effects from reads',
    () async {
      final id = await service.saveManagedFundStatement(statement());
      await service.saveManagedFundStatement(
        statement(id: id, revision: 1, voided: true),
      );
      expect(await service.getManagedFundStatementsOnce('owner'), isEmpty);
      expect(
        (await service.getManagedFundStatementsOnce(
          'owner',
          includeVoided: true,
        )).single.isVoided,
        isTrue,
      );
      expect(
        (await service.getManagedFundStatementRevisionsOnce(
          'owner',
          id,
        )).length,
        2,
      );
    },
  );
  test(
    'unreconciled reviewed capital gain components cannot be saved',
    () async {
      await expectLater(
        service.saveManagedFundStatement(
          statement(
            components: {
              'discountedCapitalGain': '10',
              'grossCapitalGain': '10',
            },
          ),
        ),
        throwsStateError,
      );
      expect(await service.getInvestmentLedgerGeneration('owner'), 0);
    },
  );
  test(
    'snapshot rejects a stale statement even with current generation',
    () async {
      final id = await service.saveManagedFundStatement(statement());
      await service.saveManagedFundStatement(
        statement(id: id, revision: 1, components: {'australianIncome': '20'}),
      );
      await expectLater(
        service.saveInvestmentCalculationSnapshot('owner', {
          'schemaVersion': 1,
          'ledgerGeneration': 2,
          'inputRevisions': <String, int>{},
          'statementRevisions': {id: 1},
          'openingLossEvidence': 'Synthetic zero direct activity',
          'snapshot': {
            'context': {'completeHistory': true, 'priorLossesReviewed': true},
          },
        }),
        throwsStateError,
      );
    },
  );
  test(
    'matching current statement snapshots retain revision provenance',
    () async {
      final id = await service.saveManagedFundStatement(statement());
      final report = await service.saveInvestmentCalculationSnapshot('owner', {
        'schemaVersion': 1,
        'ledgerGeneration': 1,
        'inputRevisions': <String, int>{},
        'statementRevisions': {id: 1},
        'openingLossEvidence': 'Synthetic zero direct activity',
        'snapshot': {
          'context': {'completeHistory': true, 'priorLossesReviewed': true},
        },
      });
      expect(report, isNotEmpty);
    },
  );
}
