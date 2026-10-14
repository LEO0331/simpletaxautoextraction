import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/document_coverage.dart';
import 'package:simpletaxautoextraction/services/parsers/broker_csv_parser.dart';
import 'package:simpletaxautoextraction/services/parsers/drp_advice_parser.dart';

void main() {
  test('One document cannot cover unrelated trades in the same account', () {
    const evidence = DocumentCoverage(
      userId: 'owner',
      taxYearStart: 2024,
      account: 'synthetic',
      ticker: 'TEST',
      family: 'brokerTrade',
      state: 'reviewed',
      evidenceReference: 'synthetic',
      linkedDomain: 'investment_transactions',
      linkedRecordId: 'trade1',
    );
    final known = [
      for (final id in ['trade1', 'trade2'])
        {
          'domain': 'investment_transactions',
          'id': id,
          'account': 'synthetic',
          'ticker': 'TEST',
          'family': 'brokerTrade',
        },
    ];
    expect(knownDocumentCoverageIssues([evidence], known).length, 1);
  });
  test('Required missing evidence blocks; reviewed provenance permits', () {
    const r = DocumentCoverage(
      userId: 'owner',
      taxYearStart: 2024,
      account: 'synthetic',
      ticker: 'TEST',
      family: 'fundAnnual',
    );
    expect(coverageIssues([r]), isNotEmpty);
    expect(
      coverageIssues([
        DocumentCoverage.fromMap({
          ...r.toMap(),
          'state': 'reviewed',
          'evidenceReference': 'synthetic statement',
        }),
      ]),
      isEmpty,
    );
  });
  test('Holdings requires exact units and valid civil date', () {
    const r = DocumentCoverage(
      userId: 'owner',
      taxYearStart: 2024,
      account: 'synthetic',
      ticker: 'TEST',
      family: 'closingHoldings',
      state: 'reviewed',
      evidenceReference: 'synthetic',
      unitsExact: '-1',
      observationDateIso: '2025-02-30',
    );
    expect(r.validation().length, 2);
    expect(parseDocumentDate('2024-02-29'), isNotNull);
  });
  const header =
      'tradeDate,direction,ticker,account,confirmationNumber,units,consideration,brokerage,totalCost,currency,broker\n';
  test('CSV retains exact amounts and PDF broker identity', () {
    final r = BrokerCsvParser()
        .parse(
          '${header}2024-07-01,BUY,TEST,synthetic,REF-1,1.23456789,10.01,0.02,10.03,AUD,CommSec',
        )
        .single;
    expect(r.draft.unitsExact, '1.23456789');
    expect(r.draft.totalCostExact, '10.03');
    expect(r.draft.sourceParser, 'CommSec Trade Confirmation Parser');
    expect(r.draft.needsReview, isTrue);
    expect(r.rawText, isEmpty);
  });
  test('Sale uses net proceeds and inconsistent money is flagged', () {
    final r = BrokerCsvParser()
        .parse(
          '${header}01/07/2024,SELL,TEST,synthetic,REF-2,2,20,1,19,AUD,CommSec',
        )
        .single;
    expect(r.missingFields, isEmpty);
    expect(r.draft.transactionType.name, 'sell');
    final bad = BrokerCsvParser()
        .parse(
          '${header}2024-07-01,SELL,TEST,synthetic,REF-3,2,20,1,21,AUD,CommSec',
        )
        .single;
    expect(bad.missingFields, contains('settlement reconciliation'));
  });
  test('Currency and malformed CSV fail closed', () {
    expect(
      () => BrokerCsvParser().parse(
        '${header}2024-07-01,BUY,TEST,synthetic,REF,1,1,0,1,USD,CommSec',
      ),
      throwsFormatException,
    );
    expect(
      () => BrokerCsvParser().parse('$header"unterminated'),
      throwsFormatException,
    );
  });
  test('Quoted amounts and missing explicit facts handled', () {
    final r = BrokerCsvParser()
        .parse(
          '${header}2024-07-01,BUY,TEST,synthetic,REF,10,"1,000.00",0,"1,000.00",AUD,CommSec',
        )
        .single;
    expect(r.draft.considerationExact, '1000');
    final empty = BrokerCsvParser()
        .parse(
          '${header}2024-07-01,,TEST,synthetic,REF,10,1000,,1000,AUD,CommSec',
        )
        .single;
    expect(empty.missingFields, containsAll(['transactionType', 'brokerage']));
  });
  test('DRP extracts only unique label facts and never guesses dates', () {
    final draft = DrpAdviceParser().parse(
      'Betashares\nDistribution Advice\nPayment date 2024-07-15\nRecord date 2024-07-01\nUnits allotted 2\nAmount reinvested 20.00\nResidual cash 1.00',
    );
    expect(draft.units, '2');
    expect(draft.issues, isEmpty);
    final ambiguous = DrpAdviceParser().parse(
      'Betashares Distribution Advice\nUnits allotted 2\nUnits allotted 3\nPayment date 15 July 2024',
    );
    expect(ambiguous.units, isNull);
    expect(ambiguous.paymentDate, '2024-07-15');
    expect(
      DrpAdviceParser()
          .parse(
            'Betashares Distribution Advice\nPayment date 31 February 2024',
          )
          .paymentDate,
      isNull,
    );
    expect(DrpAdviceParser().parse('unknown\nUnits allotted 2').units, isNull);
  });
}
