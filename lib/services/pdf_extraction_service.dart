import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/tax_record.dart';

class UnmappedExtractionEntry {
  final String sourceCategory;
  final double amount;
  final bool isIncome;

  const UnmappedExtractionEntry({
    required this.sourceCategory,
    required this.amount,
    required this.isIncome,
  });
}

class PdfExtractionResult {
  final TaxRecord record;
  final String parserName;
  final double confidence;
  final List<UnmappedExtractionEntry> unmappedEntries;
  final int mappedEntryCount;
  final int totalEntryCount;

  const PdfExtractionResult({
    required this.record,
    required this.parserName,
    required this.confidence,
    required this.unmappedEntries,
    required this.mappedEntryCount,
    required this.totalEntryCount,
  });
}

class _ParseStats {
  int mappedEntryCount = 0;
  int totalEntryCount = 0;
  final List<UnmappedExtractionEntry> unmappedEntries = [];
  final List<Map<String, dynamic>> lineItems = [];
}

class _ParserLayout {
  final String name;
  final List<String> incomeHeaders;
  final List<String> expenseHeaders;
  final List<String> stopHeaders;

  const _ParserLayout({
    required this.name,
    required this.incomeHeaders,
    required this.expenseHeaders,
    required this.stopHeaders,
  });
}

class PdfExtractionService {
  static const _forgeLayout = _ParserLayout(
    name: 'Forge Real Estate',
    incomeHeaders: ['Property Income'],
    expenseHeaders: ['Property Expenses'],
    stopHeaders: ['(GST Total:', 'PROPERTY BALANCE:', 'Owner Statement'],
  );

  static const _genericLayout = _ParserLayout(
    name: 'Generic Property Statement',
    incomeHeaders: ['Income', 'Rental Income'],
    expenseHeaders: ['Expenses', 'Rental Expenses'],
    stopHeaders: ['PROPERTY BALANCE:', 'Statement Summary', 'Owner Statement'],
  );

  /// Backward-compatible API used across the app/tests.
  Future<TaxRecord> extractFromPdf(
    List<int> bytes,
    String userId,
    String financialYear, {
    String propertyId = 'default',
    String propertyName = 'Primary Property',
    String? sourceFileName,
    Map<String, String>? customIncomeMappings,
    Map<String, String>? customExpenseMappings,
  }) async {
    final result = await extractPreviewFromPdf(
      bytes,
      userId,
      financialYear,
      propertyId: propertyId,
      propertyName: propertyName,
      sourceFileName: sourceFileName,
      customIncomeMappings: customIncomeMappings,
      customExpenseMappings: customExpenseMappings,
    );
    return result.record;
  }

  /// Returns parser metadata for import preview and manual mapping.
  Future<PdfExtractionResult> extractPreviewFromPdf(
    List<int> bytes,
    String userId,
    String financialYear, {
    String propertyId = 'default',
    String propertyName = 'Primary Property',
    String? sourceFileName,
    Map<String, String>? customIncomeMappings,
    Map<String, String>? customExpenseMappings,
  }) async {
    try {
      final document = PdfDocument(inputBytes: bytes);
      final textExtractor = PdfTextExtractor(document);
      final extractedText = textExtractor.extractText();
      document.dispose();

      return parseExtractedTextWithMetadata(
        extractedText,
        userId,
        financialYear,
        propertyId: propertyId,
        propertyName: propertyName,
        sourceFileName: sourceFileName,
        customIncomeMappings: customIncomeMappings,
        customExpenseMappings: customExpenseMappings,
      );
    } catch (e) {
      debugPrint('Error extracting PDF: $e');
      rethrow;
    }
  }

  TaxRecord parseExtractedText(
    String text,
    String userId,
    String financialYear, {
    String propertyId = 'default',
    String propertyName = 'Primary Property',
    String? sourceFileName,
    Map<String, String>? customIncomeMappings,
    Map<String, String>? customExpenseMappings,
  }) {
    return parseExtractedTextWithMetadata(
      text,
      userId,
      financialYear,
      keepUnknownAsSundry: true,
      propertyId: propertyId,
      propertyName: propertyName,
      sourceFileName: sourceFileName,
      customIncomeMappings: customIncomeMappings,
      customExpenseMappings: customExpenseMappings,
    ).record;
  }

  @visibleForTesting
  PdfExtractionResult parseExtractedTextWithMetadata(
    String text,
    String userId,
    String financialYear, {
    bool keepUnknownAsSundry = false,
    String propertyId = 'default',
    String propertyName = 'Primary Property',
    String? sourceFileName,
    Map<String, String>? customIncomeMappings,
    Map<String, String>? customExpenseMappings,
  }) {
    final lines = text.split('\n').map((line) => line.trim()).toList();
    final layout = _pickLayout(lines);
    final stats = _ParseStats();
    final record = TaxRecord.empty(
      userId,
      financialYear,
      propertyId: propertyId,
      propertyName: propertyName,
    );

    _parseWithLayout(
      lines,
      layout,
      record,
      stats,
      keepUnknownAsSundry: keepUnknownAsSundry,
      customIncomeMappings: customIncomeMappings ?? const {},
      customExpenseMappings: customExpenseMappings ?? const {},
    );

    final confidence = stats.totalEntryCount == 0
        ? 0.0
        : stats.mappedEntryCount / stats.totalEntryCount;

    return PdfExtractionResult(
      record: record.copyWith(
        sourceFileName: sourceFileName,
        sourceParser: layout.name,
        parserVersion: 'v2',
        lineItems: stats.lineItems,
      ),
      parserName: layout.name,
      confidence: confidence,
      unmappedEntries: List.unmodifiable(stats.unmappedEntries),
      mappedEntryCount: stats.mappedEntryCount,
      totalEntryCount: stats.totalEntryCount,
    );
  }

  _ParserLayout _pickLayout(List<String> lines) {
    final hasForgeIncome = lines.contains(_forgeLayout.incomeHeaders.first);
    final hasForgeExpense = lines.contains(_forgeLayout.expenseHeaders.first);
    if (hasForgeIncome || hasForgeExpense) {
      return _forgeLayout;
    }

    return _genericLayout;
  }

  void _parseWithLayout(
    List<String> lines,
    _ParserLayout layout,
    TaxRecord record,
    _ParseStats stats, {
    required bool keepUnknownAsSundry,
    required Map<String, String> customIncomeMappings,
    required Map<String, String> customExpenseMappings,
  }) {
    bool parsingIncome = false;
    bool parsingExpenses = false;

    String? currentCategory;
    final currentValues = <double>[]; // [Debit, Credit, Total]
    bool expectsGst = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (_matchesHeader(line, layout.incomeHeaders)) {
        parsingIncome = true;
        parsingExpenses = false;
        continue;
      }

      if (_matchesHeader(line, layout.expenseHeaders)) {
        parsingIncome = false;
        parsingExpenses = true;
        continue;
      }

      if (_matchesPrefix(line, layout.stopHeaders)) {
        if (parsingIncome) {
          parsingIncome = false;
        } else if (parsingExpenses) {
          break;
        }
      }

      if (!parsingIncome && !parsingExpenses) {
        continue;
      }

      final currency = _parseCurrency(line);
      if (currency != null) {
        currentValues.add(currency);
        if (currentValues.length == 3 && currentCategory != null) {
          final total = currentValues[2];

          if (expectsGst) {
            _applyAmount(
              record,
              stats,
              currentCategory,
              total,
              isIncome: parsingIncome,
              keepUnknownAsSundry: keepUnknownAsSundry,
              customIncomeMappings: customIncomeMappings,
              customExpenseMappings: customExpenseMappings,
            );
            expectsGst = false;
            currentCategory = null;
            currentValues.clear();
          } else {
            final nextHasGst =
                i + 1 < lines.length && lines[i + 1].contains('+ GST');
            _applyAmount(
              record,
              stats,
              currentCategory,
              total,
              isIncome: parsingIncome,
              keepUnknownAsSundry: keepUnknownAsSundry,
              customIncomeMappings: customIncomeMappings,
              customExpenseMappings: customExpenseMappings,
            );

            if (nextHasGst) {
              expectsGst = true;
              currentValues.clear();
            } else {
              currentCategory = null;
              currentValues.clear();
            }
          }
        }
      } else if (line.isNotEmpty && !line.contains('+ GST')) {
        currentCategory = line;
        currentValues.clear();
        expectsGst = false;
      }
    }
  }

  bool _matchesHeader(String line, List<String> headers) {
    return headers.any((header) => line == header);
  }

  bool _matchesPrefix(String line, List<String> prefixes) {
    return prefixes.any((prefix) => line.startsWith(prefix));
  }

  double? _parseCurrency(String raw) {
    if (!raw.contains(r'$')) {
      return null;
    }
    final cleaned = raw
        .replaceAll(r'$', '')
        .replaceAll(',', '')
        .replaceAll('(', '-')
        .replaceAll(')', '')
        .trim();
    return double.tryParse(cleaned);
  }

  void _applyAmount(
    TaxRecord record,
    _ParseStats stats,
    String? sourceCategory,
    double amount, {
    required bool isIncome,
    required bool keepUnknownAsSundry,
    required Map<String, String> customIncomeMappings,
    required Map<String, String> customExpenseMappings,
  }) {
    if (amount == 0 || sourceCategory == null) {
      return;
    }

    stats.totalEntryCount += 1;

    final mappedCategory = _mapCategory(
      sourceCategory,
      isIncome,
      customIncomeMappings: customIncomeMappings,
      customExpenseMappings: customExpenseMappings,
    );
    stats.lineItems.add({
      'sourceCategory': sourceCategory,
      'amount': amount,
      'isIncome': isIncome,
      'mappedCategory': mappedCategory ?? 'UNMAPPED',
    });
    if (mappedCategory != null) {
      _addToCategory(record, mappedCategory, amount, isIncome: isIncome);
      stats.mappedEntryCount += 1;
      return;
    }

    if (keepUnknownAsSundry && !isIncome) {
      _addToCategory(record, 'Sundry rental expenses', amount, isIncome: false);
      stats.mappedEntryCount += 1;
      return;
    }

    stats.unmappedEntries.add(
      UnmappedExtractionEntry(
        sourceCategory: sourceCategory,
        amount: amount,
        isIncome: isIncome,
      ),
    );
  }

  String? _mapCategory(
    String category,
    bool isIncome, {
    Map<String, String> customIncomeMappings = const {},
    Map<String, String> customExpenseMappings = const {},
  }) {
    final normalized = category.toLowerCase();
    final customMappings = isIncome
        ? customIncomeMappings
        : customExpenseMappings;
    for (final entry in customMappings.entries) {
      if (normalized.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }

    if (isIncome) {
      if (normalized.contains('rent')) {
        return 'Gross rent';
      }
      if (normalized.contains('income') ||
          normalized.contains('reimburse') ||
          normalized.contains('water')) {
        return 'Other rental-related income';
      }
      return null;
    }

    if (normalized.contains('administration fee') ||
        normalized.contains('letting fee') ||
        normalized.contains('management fee') ||
        normalized.contains('agent')) {
      return 'Property agent fees and commission';
    }
    if (normalized.contains('repair') || normalized.contains('maintenance')) {
      return 'Repairs and maintenance';
    }
    if (normalized.contains('insurance')) {
      return 'Insurance';
    }
    if (normalized.contains('council')) {
      return 'Council rates';
    }
    if (normalized.contains('water')) {
      return 'Water charges';
    }
    if (normalized.contains('interest')) {
      return 'Interest on loans';
    }
    if (normalized.contains('clean')) {
      return 'Cleaning';
    }
    if (normalized.contains('garden') || normalized.contains('lawn')) {
      return 'Gardening and lawn mowing';
    }
    if (normalized.contains('advertis')) {
      return 'Advertising for tenants';
    }
    if (normalized.contains('body corporate')) {
      return 'Body corporate fees and charges';
    }
    if (normalized.contains('legal')) {
      return 'Legal expenses';
    }
    if (normalized.contains('land tax')) {
      return 'Land tax';
    }

    return null;
  }

  void _addToCategory(
    TaxRecord record,
    String category,
    double amount, {
    required bool isIncome,
  }) {
    if (isIncome) {
      record.income[category] = (record.income[category] ?? 0.0) + amount;
    } else {
      record.expenses[category] = (record.expenses[category] ?? 0.0) + amount;
    }
  }

  /// Maps category to ATO worksheet and defaults unknown expense lines to sundry.
  @visibleForTesting
  void addValueToAtoCategory(
    TaxRecord record,
    String category,
    double amount, {
    required bool isIncome,
  }) {
    if (amount == 0) {
      return;
    }

    final mapped = _mapCategory(category, isIncome);
    if (mapped != null) {
      _addToCategory(record, mapped, amount, isIncome: isIncome);
      return;
    }

    if (isIncome) {
      _addToCategory(
        record,
        'Other rental-related income',
        amount,
        isIncome: true,
      );
      return;
    }

    _addToCategory(record, 'Sundry rental expenses', amount, isIncome: false);
  }
}
