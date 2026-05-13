import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/investment_transaction.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/services/firestore_service.dart';

void main() {
  group('FirestoreService extended', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = FirestoreService(db: fakeFirestore);
    });

    test(
      'saveTaxRecordWithStrategy replaces same year/property record',
      () async {
        const userId = 'u1';
        await service.saveTaxRecordWithStrategy(
          TaxRecord(
            userId: userId,
            financialYear: '2024-2025',
            propertyId: 'p1',
            income: {'Gross rent': 1000},
          ),
        );

        final result = await service.saveTaxRecordWithStrategy(
          TaxRecord(
            userId: userId,
            financialYear: '2024-2025',
            propertyId: 'p1',
            income: {'Gross rent': 2000},
          ),
        );

        expect(result.replacedExistingYear, isTrue);
        final records = await service.getUserTaxRecords(userId).first;
        expect(records.length, 1);
        expect(records.first.totalIncome, 2000);
      },
    );

    test('findRecordByYear respects property filter', () async {
      const userId = 'u1';
      await service.saveTaxRecordWithStrategy(
        TaxRecord(userId: userId, financialYear: '2024-2025', propertyId: 'pA'),
      );

      final match = await service.findRecordByYear(
        userId,
        '2024-2025',
        propertyId: 'pA',
      );
      final miss = await service.findRecordByYear(
        userId,
        '2024-2025',
        propertyId: 'pB',
      );

      expect(match, isNotNull);
      expect(miss, isNull);
    });

    test('custom mappings and property streams persist', () async {
      const userId = 'u1';
      await service.saveCustomMappings(
        userId,
        {'rent rebate': 'Other rental-related income'},
        {'strata': 'Body corporate fees and charges'},
      );
      await service.saveProperty(
        userId,
        const PropertyInfo(id: 'p123', name: 'Apartment 123'),
      );

      final mappings = await service.getCustomMappings(userId);
      final properties = await service.getUserProperties(userId).first;

      expect(mappings['income']!['rent rebate'], 'Other rental-related income');
      expect(mappings['expense']!['strata'], 'Body corporate fees and charges');
      expect(properties.any((p) => p.name == 'Apartment 123'), isTrue);
    });

    test('investment transaction save and duplicate detection', () async {
      const userId = 'u1';
      final tx = InvestmentTransaction(
        userId: userId,
        ticker: 'NDQ',
        securityName: 'ETF',
        transactionType: InvestmentTransactionType.buy,
        tradeDate: DateTime(2026, 3, 30),
        units: 80,
        averagePrice: 49.66,
        consideration: 3972.8,
        brokerage: 7.94,
        totalCost: 3980.74,
        confirmationNumber: 'C173462109',
        sourceParser: 'test',
        parserVersion: 'v1',
      );

      final id = await service.saveInvestmentTransaction(tx);
      final list = await service.getInvestmentTransactionsOnce(userId);
      expect(id, isNotEmpty);
      expect(list.length, 1);

      final duplicate = await service.findInvestmentDuplicate(
        userId,
        tx.copyWith(confirmationNumber: 'C173462109'),
      );
      expect(duplicate, isNotNull);
    });
  });
}
