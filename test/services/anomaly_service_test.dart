import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';
import 'package:simpletaxautoextraction/services/anomaly_service.dart';

void main() {
  group('AnomalyService', () {
    final service = AnomalyService();

    test('returns empty when there are fewer than two records', () {
      final records = [
        TaxRecord(
          userId: 'u1',
          financialYear: '2024-2025',
          income: {'Gross rent': 10000},
          expenses: {'Water charges': 2000},
        ),
      ];

      expect(service.detectYearlyAnomalies(records), isEmpty);
    });

    test('detects large income and expense deltas', () {
      final records = [
        TaxRecord(
          userId: 'u1',
          financialYear: '2023-2024',
          income: {'Gross rent': 10000},
          expenses: {'Water charges': 2000},
        ),
        TaxRecord(
          userId: 'u1',
          financialYear: '2024-2025',
          income: {'Gross rent': 15000},
          expenses: {'Water charges': 3500},
        ),
      ];

      final alerts = service.detectYearlyAnomalies(records);
      expect(alerts.length, 2);
      expect(alerts.first, contains('income changed'));
      expect(alerts.last, contains('expenses changed'));
    });

    test('handles previous zero values', () {
      final records = [
        TaxRecord(userId: 'u1', financialYear: '2023-2024'),
        TaxRecord(
          userId: 'u1',
          financialYear: '2024-2025',
          income: {'Gross rent': 5000},
          expenses: {'Water charges': 100},
        ),
      ];

      final alerts = service.detectYearlyAnomalies(records);
      expect(alerts, isNotEmpty);
    });
  });
}
