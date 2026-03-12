import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/services/pdf_extraction_service.dart';
import 'package:simpletaxautoextraction/models/tax_record.dart';

void main() {
  group('PdfExtractionService Parsing Logic', () {
    late PdfExtractionService service;
    const userId = 'test_user';
    const financialYear = '2024-2025';

    setUp(() {
      service = PdfExtractionService();
    });

    test('parseExtractedText correctly parses property income', () {
      const text = '''
Property Income
Rent
\$1,000.00
\$0.00
\$1,000.00
PROPERTY BALANCE:
''';
      final record = service.parseExtractedText(text, userId, financialYear);
      
      expect(record.income['Gross rent'], 1000.00);
      expect(record.totalIncome, 1000.00);
    });

    test('parseExtractedText correctly parses property expenses', () {
      final text = 'Property Expenses\n'
          'Management Fee\n'
          '\$0.00\n'
          '\$55.00\n'
          '\$55.00\n'
          'Council Rates\n'
          '\$0.00\n'
          '\$300.00\n'
          '\$300.00\n'
          'PROPERTY BALANCE:';
      final record = service.parseExtractedText(text, userId, financialYear);
      print('Parsed Expenses: \n${record.expenses}');
      
      expect(record.expenses['Property agent fees and commission'], 55.00);
      expect(record.expenses['Council rates'], 300.00);
      expect(record.totalExpenses, 355.00);
    });

    test('parseExtractedText handles GST lines', () {
      const text = '''
Property Expenses
Repairs
\$0.00
\$100.00
\$100.00
   + GST
\$0.00
\$10.00
\$10.00
PROPERTY BALANCE:
''';
      final record = service.parseExtractedText(text, userId, financialYear);
      
      // The logic adds both base and GST to the category
      expect(record.expenses['Repairs and maintenance'], 110.00);
    });

    test('addValueToAtoCategory maps various categories correctly', () {
      final record = TaxRecord.empty(userId, financialYear);
      
      service.addValueToAtoCategory(record, 'Letting Fee', 100.0, isIncome: false);
      expect(record.expenses['Property agent fees and commission'], 100.0);
      
      service.addValueToAtoCategory(record, 'Water Rates', 50.0, isIncome: false);
      expect(record.expenses['Water charges'], 50.0);
      
      service.addValueToAtoCategory(record, 'Insurance Premium', 200.0, isIncome: false);
      expect(record.expenses['Insurance'], 200.0);
      
      service.addValueToAtoCategory(record, 'Interest', 500.0, isIncome: false);
      expect(record.expenses['Interest on loans'], 500.0);
      
      service.addValueToAtoCategory(record, 'Unknown Expense', 20.0, isIncome: false);
      expect(record.expenses['Sundry rental expenses'], 20.0);
    });

    test('addValueToAtoCategory maps income correctly', () {
      final record = TaxRecord.empty(userId, financialYear);
      
      service.addValueToAtoCategory(record, 'Weekly Rent', 2000.0, isIncome: true);
      expect(record.income['Gross rent'], 2000.0);
      
      service.addValueToAtoCategory(record, 'Reimbursement', 100.0, isIncome: true);
      expect(record.income['Other rental-related income'], 100.0);
    });
  });
}
