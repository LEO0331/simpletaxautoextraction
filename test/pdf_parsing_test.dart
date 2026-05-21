import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/services/pdf_extraction_service.dart';

void main() {
  group('PdfExtractionService - Text Parsing Logic', () {
    // We simulate the exact text output that Syncfusion extracts from
    // the Forge Real Estate Income & Expenditure Summary PDF.

    group('Income parsing', () {
      test('parses Residential Rent as Gross rent', () async {
        // This simulates an actual PDF's extracted text
        final simulatedText = _buildSimulatedPdfText(
          incomeLines: [
            'Residential Rent',
            '\$0.00',
            '\$14,340.00',
            '\$14,340.00',
          ],
          expenseLines: [],
        );

        final record = await _extractFromSimulatedText(simulatedText);

        expect(record.income['Gross rent'], 14340.00);
      });

      test('parses Water Rates as Other rental-related income', () async {
        final simulatedText = _buildSimulatedPdfText(
          incomeLines: ['Water Rates', '\$0.00', '\$76.41', '\$76.41'],
          expenseLines: [],
        );

        final record = await _extractFromSimulatedText(simulatedText);

        expect(record.income['Other rental-related income'], 76.41);
      });

      test('accumulates multiple income categories', () async {
        final simulatedText = _buildSimulatedPdfText(
          incomeLines: [
            'Residential Rent',
            '\$0.00',
            '\$14,340.00',
            '\$14,340.00',
            'Water Rates',
            '\$0.00',
            '\$76.41',
            '\$76.41',
          ],
          expenseLines: [],
        );

        final record = await _extractFromSimulatedText(simulatedText);

        expect(record.income['Gross rent'], 14340.00);
        expect(record.income['Other rental-related income'], 76.41);
        expect(record.totalIncome, closeTo(14416.41, 0.01));
      });
    });

    group('Expense parsing', () {
      test('maps Administration Fee to agent fees', () async {
        final simulatedText = _buildSimulatedPdfText(
          incomeLines: [],
          expenseLines: [
            'Administration Fee',
            '\$8.00',
            '\$2.00',
            '\$6.00',
            '   + GST',
            '\$0.80',
            '\$0.20',
            '\$0.60',
          ],
        );

        final record = await _extractFromSimulatedText(simulatedText);

        expect(
          record.expenses['Property agent fees and commission'],
          closeTo(6.60, 0.01),
        );
      });

      test('maps Landlord Insurance to Insurance', () async {
        final simulatedText = _buildSimulatedPdfText(
          incomeLines: [],
          expenseLines: [
            'Landlord Insurance',
            '\$288.18',
            '\$0.00',
            '\$288.18',
            '   + GST',
            '\$28.82',
            '\$0.00',
            '\$28.82',
          ],
        );

        final record = await _extractFromSimulatedText(simulatedText);

        expect(record.expenses['Insurance'], closeTo(317.00, 0.01));
      });

      test('maps General Repairs and Maintenance', () async {
        final simulatedText = _buildSimulatedPdfText(
          incomeLines: [],
          expenseLines: [
            'General Repairs and Maintenance',
            '\$90.00',
            '\$0.00',
            '\$90.00',
            '   + GST',
            '\$9.00',
            '\$0.00',
            '\$9.00',
          ],
        );

        final record = await _extractFromSimulatedText(simulatedText);

        expect(
          record.expenses['Repairs and maintenance'],
          closeTo(99.00, 0.01),
        );
      });

      test('maps Letting Fee to agent fees', () async {
        final simulatedText = _buildSimulatedPdfText(
          incomeLines: [],
          expenseLines: [
            'Letting Fee',
            '\$550.03',
            '\$0.00',
            '\$550.03',
            '   + GST',
            '\$55.00',
            '\$0.00',
            '\$55.00',
          ],
        );

        final record = await _extractFromSimulatedText(simulatedText);

        expect(
          record.expenses['Property agent fees and commission'],
          closeTo(605.03, 0.01),
        );
      });

      test('maps Residential Management Fee to agent fees', () async {
        final simulatedText = _buildSimulatedPdfText(
          incomeLines: [],
          expenseLines: [
            'Residential Management Fee',
            '\$478.00',
            '\$119.50',
            '\$358.50',
            '   + GST',
            '\$47.80',
            '\$11.95',
            '\$35.85',
          ],
        );

        final record = await _extractFromSimulatedText(simulatedText);

        expect(
          record.expenses['Property agent fees and commission'],
          closeTo(394.35, 0.01),
        );
      });
    });

    group('Full document parsing', () {
      test('parses complete Forge Real Estate PDF text', () async {
        final simulatedText = _buildFullForgeRealEstateText();
        final record = await _extractFromSimulatedText(simulatedText);

        // Income
        expect(record.income['Gross rent'], 14340.00);
        expect(record.income['Other rental-related income'], 76.41);
        expect(record.totalIncome, closeTo(14416.41, 0.01));

        // Expenses (base + GST)
        expect(record.expenses['Insurance'], closeTo(317.00, 0.01));
        expect(
          record.expenses['Repairs and maintenance'],
          closeTo(99.00, 0.01),
        );

        // Agent fees = Admin(6+0.60) + Letting(550.03+55) + Management(358.50+35.85)
        expect(
          record.expenses['Property agent fees and commission'],
          closeTo(1005.98, 0.01),
        );

        expect(record.totalExpenses, closeTo(1421.98, 0.01));
        expect(record.netPosition, closeTo(12994.43, 0.01));
      });

      test('zero-value income items do not inflate totals', () async {
        final simulatedText = _buildSimulatedPdfText(
          incomeLines: ['Residential Rent', '\$0.00', '\$0.00', '\$0.00'],
          expenseLines: [],
        );

        final record = await _extractFromSimulatedText(simulatedText);
        expect(record.income['Gross rent'], 0.0);
        expect(record.totalIncome, 0.0);
      });

      test('empty text returns empty ATO template', () async {
        final record = await _extractFromSimulatedText('');
        expect(record.totalIncome, 0.0);
        expect(record.totalExpenses, 0.0);
        expect(record.netPosition, 0.0);
      });
    });

    group('Edge cases', () {
      test('handles large currency values', () async {
        final simulatedText = _buildSimulatedPdfText(
          incomeLines: [
            'Residential Rent',
            '\$0.00',
            '\$123,456.78',
            '\$123,456.78',
          ],
          expenseLines: [],
        );

        final record = await _extractFromSimulatedText(simulatedText);
        expect(record.income['Gross rent'], 123456.78);
      });

      test('handles expense without GST line', () async {
        // Some PDFs might not have GST lines
        final simulatedText = _buildSimulatedPdfText(
          incomeLines: [],
          expenseLines: ['Council Rates', '\$1,200.00', '\$0.00', '\$1,200.00'],
        );

        final record = await _extractFromSimulatedText(simulatedText);
        expect(record.expenses['Council rates'], 1200.00);
      });

      test('unknown expense category falls to Sundry', () async {
        final simulatedText = _buildSimulatedPdfText(
          incomeLines: [],
          expenseLines: [
            'Some Random Category',
            '\$50.00',
            '\$0.00',
            '\$50.00',
          ],
        );

        final record = await _extractFromSimulatedText(simulatedText);
        expect(record.expenses['Sundry rental expenses'], 50.00);
      });
    });
  });
}

// ─── Helpers ─────────────────────────────────────────────────────

/// Creates a simulated PDF text structure matching the Forge RE layout.
String _buildSimulatedPdfText({
  required List<String> incomeLines,
  required List<String> expenseLines,
}) {
  final buf = StringBuffer();
  buf.writeln('Page 1 of 1');
  buf.writeln('Some Header Text');

  if (incomeLines.isNotEmpty) {
    buf.writeln('Property Income');
    for (final line in incomeLines) {
      buf.writeln(line);
    }
    buf.writeln('(GST Total: \$0.00)');
  }

  if (expenseLines.isNotEmpty) {
    buf.writeln('Property Expenses');
    for (final line in expenseLines) {
      buf.writeln(line);
    }
    buf.writeln('(GST Total: \$0.00)');
  }

  buf.writeln('PROPERTY BALANCE: \$0.00');
  return buf.toString();
}

/// Builds a full simulated text matching 2025_rent_fortax.pdf extraction.
String _buildFullForgeRealEstateText() {
  return '''
Page 1 of 2
Li Cheng Chen
3/291 Waverley Road
Mount Waverley VIC 3149
Date 1/07/2024 to 30/06/2025
Property Income
Residential Rent
\$0.00
\$14,340.00
\$14,340.00
Water Rates
\$0.00
\$76.41
\$76.41
(GST Total: \$0.00)
Property Expenses
Administration Fee
\$8.00
\$2.00
\$6.00
   + GST
\$0.80
\$0.20
\$0.60
General Repairs and Maintenance
\$90.00
\$0.00
\$90.00
   + GST
\$9.00
\$0.00
\$9.00
Landlord Insurance
\$288.18
\$0.00
\$288.18
   + GST
\$28.82
\$0.00
\$28.82
Letting Fee
\$550.03
\$0.00
\$550.03
   + GST
\$55.00
\$0.00
\$55.00
Residential Management Fee
\$478.00
\$119.50
\$358.50
   + GST
\$47.80
\$11.95
\$35.85
(GST Total: \$129.27)
PROPERTY BALANCE: \$12,994.43
''';
}

Future<dynamic> _extractFromSimulatedText(String text) async {
  return PdfExtractionService().parseExtractedText(
    text,
    'test_user',
    '2024-2025',
  );
}
