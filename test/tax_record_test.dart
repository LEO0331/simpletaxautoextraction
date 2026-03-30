import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';

void main() {
  group('TaxRecord Model', () {
    group('Constructor', () {
      test('creates with required fields and defaults', () {
        final record = TaxRecord(userId: 'user1', financialYear: '2024-2025');

        expect(record.userId, 'user1');
        expect(record.financialYear, '2024-2025');
        expect(record.id, isNull);
        expect(record.income, isEmpty);
        expect(record.expenses, isEmpty);
      });

      test('creates with all fields provided', () {
        final record = TaxRecord(
          id: 'doc123',
          userId: 'user1',
          financialYear: '2024-2025',
          income: {'Gross rent': 14340.00},
          expenses: {'Insurance': 317.00},
        );

        expect(record.id, 'doc123');
        expect(record.income['Gross rent'], 14340.00);
        expect(record.expenses['Insurance'], 317.00);
      });

      test('null income/expenses default to empty maps', () {
        final record = TaxRecord(
          userId: 'user1',
          financialYear: '2024-2025',
          income: null,
          expenses: null,
        );

        expect(record.income, isA<Map<String, double>>());
        expect(record.expenses, isA<Map<String, double>>());
        expect(record.income, isEmpty);
        expect(record.expenses, isEmpty);
      });
    });

    group('Computed Properties', () {
      test('totalIncome sums all income values', () {
        final record = TaxRecord(
          userId: 'user1',
          financialYear: '2024-2025',
          income: {
            'Gross rent': 14340.00,
            'Other rental-related income': 76.41,
          },
        );

        expect(record.totalIncome, closeTo(14416.41, 0.01));
      });

      test('totalExpenses sums all expense values', () {
        final record = TaxRecord(
          userId: 'user1',
          financialYear: '2024-2025',
          expenses: {
            'Insurance': 317.00,
            'Property agent fees and commission': 1005.98,
            'Repairs and maintenance': 99.00,
          },
        );

        expect(record.totalExpenses, closeTo(1421.98, 0.01));
      });

      test('netPosition calculates income minus expenses', () {
        final record = TaxRecord(
          userId: 'user1',
          financialYear: '2024-2025',
          income: {'Gross rent': 14416.41},
          expenses: {'Insurance': 1421.98},
        );

        expect(record.netPosition, closeTo(12994.43, 0.01));
      });

      test('netPosition is negative when expenses exceed income', () {
        final record = TaxRecord(
          userId: 'user1',
          financialYear: '2024-2025',
          income: {'Gross rent': 5000.00},
          expenses: {'Interest on loans': 12000.00},
        );

        expect(record.netPosition, closeTo(-7000.00, 0.01));
        expect(record.netPosition, isNegative);
      });

      test('totalIncome is 0 for empty income map', () {
        final record = TaxRecord(userId: 'user1', financialYear: '2024-2025');
        expect(record.totalIncome, 0.0);
      });

      test('totalExpenses is 0 for empty expenses map', () {
        final record = TaxRecord(userId: 'user1', financialYear: '2024-2025');
        expect(record.totalExpenses, 0.0);
      });
    });

    group('TaxRecord.empty()', () {
      test('creates record with all ATO income categories at zero', () {
        final record = TaxRecord.empty('user1', '2024-2025');

        expect(record.income.containsKey('Gross rent'), isTrue);
        expect(
          record.income.containsKey('Other rental-related income'),
          isTrue,
        );
        expect(record.income.length, 2);
        expect(record.income.values.every((v) => v == 0.0), isTrue);
      });

      test('creates record with all ATO expense categories at zero', () {
        final record = TaxRecord.empty('user1', '2024-2025');

        final expectedCategories = [
          'Advertising for tenants',
          'Body corporate fees and charges',
          'Borrowing expenses',
          'Cleaning',
          'Council rates',
          'Capital works deductions',
          'Gardening and lawn mowing',
          'Insurance',
          'Interest on loans',
          'Land tax',
          'Legal expenses',
          'Pest control',
          'Property agent fees and commission',
          'Repairs and maintenance',
          'Stationery, telephone and postage',
          'Water charges',
          'Sundry rental expenses',
        ];

        for (final cat in expectedCategories) {
          expect(
            record.expenses.containsKey(cat),
            isTrue,
            reason: 'Missing ATO category: $cat',
          );
        }
        expect(record.expenses.length, expectedCategories.length);
        expect(record.expenses.values.every((v) => v == 0.0), isTrue);
      });

      test('sets userId and financialYear correctly', () {
        final record = TaxRecord.empty('abc_user', '2023-2024');
        expect(record.userId, 'abc_user');
        expect(record.financialYear, '2023-2024');
        expect(record.id, isNull);
      });
    });

    group('Serialization', () {
      test('fromMap creates a valid TaxRecord', () {
        final data = {
          'userId': 'user1',
          'financialYear': '2024-2025',
          'income': {'Gross rent': 14340.0},
          'expenses': {'Insurance': 317.0, 'Repairs and maintenance': 99.0},
        };

        final record = TaxRecord.fromMap(data, 'doc_abc');

        expect(record.id, 'doc_abc');
        expect(record.userId, 'user1');
        expect(record.financialYear, '2024-2025');
        expect(record.income['Gross rent'], 14340.0);
        expect(record.expenses['Insurance'], 317.0);
        expect(record.expenses['Repairs and maintenance'], 99.0);
      });

      test('fromMap handles missing fields gracefully', () {
        final record = TaxRecord.fromMap({}, 'doc_xyz');

        expect(record.id, 'doc_xyz');
        expect(record.userId, '');
        expect(record.financialYear, '');
        expect(record.income, isEmpty);
        expect(record.expenses, isEmpty);
      });

      test('toMap produces correct structure', () {
        final record = TaxRecord(
          userId: 'user1',
          financialYear: '2024-2025',
          income: {'Gross rent': 14340.0},
          expenses: {'Insurance': 317.0},
        );

        final map = record.toMap();

        expect(map['userId'], 'user1');
        expect(map['financialYear'], '2024-2025');
        expect(map['income'], {'Gross rent': 14340.0});
        expect(map['expenses'], {'Insurance': 317.0});
        expect(map.containsKey('createdAt'), isFalse);
        expect(map.containsKey('updatedAt'), isFalse);
      });

      test('fromMap -> toMap round-trip preserves data', () {
        final originalData = {
          'userId': 'user1',
          'financialYear': '2024-2025',
          'income': {
            'Gross rent': 14340.0,
            'Other rental-related income': 76.41,
          },
          'expenses': {'Insurance': 317.0, 'Repairs and maintenance': 99.0},
        };

        final record = TaxRecord.fromMap(originalData, 'doc_abc');
        final roundTripped = record.toMap();

        expect(roundTripped['userId'], originalData['userId']);
        expect(roundTripped['financialYear'], originalData['financialYear']);
        expect(roundTripped['income'], originalData['income']);
        expect(roundTripped['expenses'], originalData['expenses']);
      });
    });
  });
}
