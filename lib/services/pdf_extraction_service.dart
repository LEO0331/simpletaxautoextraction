import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/tax_record.dart';

class PdfExtractionService {
  /// Extracts text from a simple PDF and maps it to a TaxRecord
  Future<TaxRecord> extractFromPdf(
      List<int> bytes, String userId, String financialYear) async {
    try {
      final document = PdfDocument(inputBytes: bytes);
      final textExtractor = PdfTextExtractor(document);
      String extractedText = textExtractor.extractText();
      document.dispose();

      return parseExtractedText(extractedText, userId, financialYear);
    } catch (e) {
      debugPrint('Error extracting PDF: $e');
      rethrow;
    }
  }

  @visibleForTesting
  TaxRecord parseExtractedText(
      String text, String userId, String financialYear) {
    // Start with an empty ATO template
    final record = TaxRecord.empty(userId, financialYear);

    final lines = text.split('\n').map((e) => e.trim()).toList();

    bool parsingIncome = false;
    bool parsingExpenses = false;

    String? currentCategory;
    List<double> currentValues = []; // Expecting [Debit, Credit, Total]
    bool expectsGst = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line == 'Property Income') {
        parsingIncome = true;
        parsingExpenses = false;
        continue;
      } else if (line == 'Property Expenses') {
        parsingIncome = false;
        parsingExpenses = true;
        continue;
      } else if (line.startsWith('(GST Total:') ||
          line.startsWith('PROPERTY BALANCE:')) {
        if (parsingIncome) {
          parsingIncome = false;
        } else if (parsingExpenses) {
          parsingExpenses = false;
          // After Property Expenses and its GST total, usually we hit Property Balance or Owner ...
          break; // Optimization: we don't need to parse the rest of the Owner section unless necessary
        }
      }

      if (!parsingIncome && !parsingExpenses) continue;

      // Check if line is a currency line
      if (line.startsWith('\$')) {
        final val = _parseCurrency(line);
        if (val != null) {
          currentValues.add(val);

          // In this specific PDF, values are grouped in threes: Debit, Credit, Total.
          // Then potentially GST values.
          if (currentValues.length == 3 && currentCategory != null) {
            final total = currentValues[2]; // The third value is "Total"
            
            if (expectsGst) {
              // Add GST total to our previous category mapped value if necessary 
              // (usually we map the full value including GST for deductions, subject to user's GST registration)
              // Let's assume standard residential landlords add GST to the total expense.
              addValueToAtoCategory(record, currentCategory!, total,
                  isIncome: parsingIncome);
              expectsGst = false;
              currentCategory = null;
              currentValues.clear();
            } else {
              // Look ahead to see if the next line is "   + GST"
              if (i + 1 < lines.length && lines[i + 1].contains('+ GST')) {
                expectsGst = true;
                // Save the base total to be added with the GST total later, 
                // but actually it's easier to just add them as we see them.
                addValueToAtoCategory(record, currentCategory!, total,
                    isIncome: parsingIncome);
                currentValues.clear(); // Clear to collect the 3 GST values
              } else {
                // No GST follows, commit the total
                addValueToAtoCategory(record, currentCategory!, total,
                    isIncome: parsingIncome);
                currentCategory = null;
                currentValues.clear();
              }
            }
          }
        }
      } else if (line.isNotEmpty && !line.contains('+ GST')) {
        // Assume non-empty, non-currency, non-GST lines are category headers
        currentCategory = line;
        currentValues.clear();
        expectsGst = false;
      }
    }

    return record;
  }

  double? _parseCurrency(String val) {
    try {
      final cleaned = val.replaceAll('\$', '').replaceAll(',', '').trim();
      return double.tryParse(cleaned);
    } catch (_) {
      return null;
    }
  }

  /// Maps the Forge Real Estate category to ATO Worksheet Category
  @visibleForTesting
  void addValueToAtoCategory(TaxRecord record, String category, double amount,
      {required bool isIncome}) {
    if (amount == 0) return;

    if (isIncome) {
      if (category.toLowerCase().contains('rent')) {
        record.income['Gross rent'] =
            (record.income['Gross rent'] ?? 0.0) + amount;
      } else {
        record.income['Other rental-related income'] =
            (record.income['Other rental-related income'] ?? 0.0) + amount;
      }
    } else {
      category = category.toLowerCase();
      if (category.contains('administration fee') ||
          category.contains('letting fee') ||
          category.contains('management fee')) {
        record.expenses['Property agent fees and commission'] =
            (record.expenses['Property agent fees and commission'] ?? 0.0) +
                amount;
      } else if (category.contains('repair') ||
          category.contains('maintenance')) {
        record.expenses['Repairs and maintenance'] =
            (record.expenses['Repairs and maintenance'] ?? 0.0) + amount;
      } else if (category.contains('insurance')) {
        record.expenses['Insurance'] =
            (record.expenses['Insurance'] ?? 0.0) + amount;
      } else if (category.contains('council')) {
        record.expenses['Council rates'] =
            (record.expenses['Council rates'] ?? 0.0) + amount;
      } else if (category.contains('water') || category.contains('rates')) {
        record.expenses['Water charges'] =
            (record.expenses['Water charges'] ?? 0.0) + amount;
      } else if (category.contains('interest')) {
        record.expenses['Interest on loans'] =
            (record.expenses['Interest on loans'] ?? 0.0) + amount;
      } else {
        record.expenses['Sundry rental expenses'] =
            (record.expenses['Sundry rental expenses'] ?? 0.0) + amount;
      }
    }
  }
}
