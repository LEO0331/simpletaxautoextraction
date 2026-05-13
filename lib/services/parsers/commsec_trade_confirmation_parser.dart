import '../../models/investment_transaction.dart';
import '../../utils/investment_cgt_utils.dart';

class InvestmentTransactionDraft {
  final String ticker;
  final String securityName;
  final InvestmentTransactionType transactionType;
  final DateTime? tradeDate;
  final DateTime? settlementDate;
  final double? units;
  final double? averagePrice;
  final double? consideration;
  final double? brokerage;
  final double? gst;
  final double? totalCost;
  final String? confirmationNumber;
  final String? accountNumber;
  final String? sourceFileName;
  final String sourceParser;
  final String parserVersion;
  final String notes;
  final bool needsReview;

  const InvestmentTransactionDraft({
    required this.ticker,
    required this.securityName,
    required this.transactionType,
    required this.tradeDate,
    required this.settlementDate,
    required this.units,
    required this.averagePrice,
    required this.consideration,
    required this.brokerage,
    required this.gst,
    required this.totalCost,
    required this.confirmationNumber,
    required this.accountNumber,
    required this.sourceFileName,
    required this.sourceParser,
    required this.parserVersion,
    required this.notes,
    required this.needsReview,
  });

  InvestmentTransaction toTransaction(String userId) {
    return InvestmentTransaction(
      userId: userId,
      ticker: ticker,
      securityName: securityName,
      transactionType: transactionType,
      tradeDate: tradeDate ?? DateTime.now(),
      settlementDate: settlementDate,
      units: units ?? 0,
      averagePrice: averagePrice ?? 0,
      consideration: consideration ?? 0,
      brokerage: brokerage ?? 0,
      gst: gst,
      totalCost: totalCost ?? ((consideration ?? 0) + (brokerage ?? 0)),
      confirmationNumber: confirmationNumber,
      accountNumber: accountNumber,
      sourceFileName: sourceFileName,
      sourceParser: sourceParser,
      parserVersion: parserVersion,
      notes: notes,
      isLocked: false,
    );
  }
}

class InvestmentExtractionResult {
  final InvestmentTransactionDraft draft;
  final double confidence;
  final List<String> missingFields;
  final List<String> warnings;
  final String rawText;

  const InvestmentExtractionResult({
    required this.draft,
    required this.confidence,
    required this.missingFields,
    required this.warnings,
    required this.rawText,
  });
}

class CommsecTradeConfirmationParser {
  static const String parserName = 'CommSec Trade Confirmation Parser';
  static const String parserVersion = 'v1';

  InvestmentExtractionResult parse(String rawText, {String? sourceFileName}) {
    final text = rawText.replaceAll('\r', '\n');
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final missing = <String>[];
    final warnings = <String>[];

    final ticker = _extractTicker(text, lines);
    final securityName = _extractSecurityName(text, lines);
    final type = _extractTransactionType(text);
    final tradeDate = _extractDate(text, ['TRADE DATE', 'DATE', 'AS AT DATE']);
    final settlementDate = _extractDate(text, ['SETTLEMENT DATE']);
    final units = _extractMoneyLike(text, ['TOTAL UNITS', 'UNITS']);
    final averagePrice = _extractMoneyLike(text, ['AVERAGE PRICE']);
    final consideration = _extractMoneyLike(text, ['CONSIDERATION']);
    final brokerage = _extractMoneyLike(text, ['BROKERAGE & COSTS INCL GST']);
    final gst = _extractMoneyLike(text, ['TOTAL GST']);
    double? totalCost = _extractMoneyLike(text, ['TOTAL COST']);
    final confirmationNumber = _extractAfterLabel(text, [
      'CONFIRMATION NO',
      'CONFIRMATION NUMBER',
    ]);
    final accountNumber = _extractAfterLabel(text, ['ACCOUNT NO', 'ACCOUNT']);

    if (totalCost == null && consideration != null && brokerage != null) {
      totalCost = consideration + brokerage;
      warnings.add('TOTAL COST missing; used consideration + brokerage.');
    }

    if (ticker.isEmpty) missing.add('ticker');
    if (securityName.isEmpty) missing.add('securityName');
    if (tradeDate == null) missing.add('tradeDate');
    if (units == null || units <= 0) missing.add('units');
    if (averagePrice == null || averagePrice <= 0) missing.add('averagePrice');
    if (totalCost == null || totalCost <= 0) missing.add('totalCost');

    final score = _confidence(missing.length, warnings.length);
    final needsReview = missing.isNotEmpty || warnings.isNotEmpty;

    return InvestmentExtractionResult(
      draft: InvestmentTransactionDraft(
        ticker: ticker,
        securityName: securityName,
        transactionType: type,
        tradeDate: tradeDate,
        settlementDate: settlementDate,
        units: units,
        averagePrice: averagePrice,
        consideration: consideration,
        brokerage: brokerage,
        gst: gst,
        totalCost: totalCost,
        confirmationNumber: confirmationNumber,
        accountNumber: accountNumber,
        sourceFileName: sourceFileName,
        sourceParser: parserName,
        parserVersion: parserVersion,
        notes: '',
        needsReview: needsReview,
      ),
      confidence: score,
      missingFields: missing,
      warnings: warnings,
      rawText: rawText,
    );
  }

  String _extractTicker(String text, List<String> lines) {
    final codeRe = RegExp(r'\b([A-Z]{2,6})\b');
    final inlineCodeRe = RegExp(
      r'(?:SECURITY\s+CODE|CODE)\s*[:\-]?\s*([A-Z]{2,6})\b',
      caseSensitive: false,
    );
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final inlineMatch = inlineCodeRe.firstMatch(line);
      if (inlineMatch != null) {
        return inlineMatch.group(1)!.toUpperCase();
      }

      final normalized = line.toUpperCase();
      if (normalized.contains('SECURITY CODE') || normalized == 'CODE') {
        final maybe = i + 1 < lines.length ? lines[i + 1].toUpperCase() : '';
        final m = codeRe.firstMatch(maybe);
        if (m != null) return m.group(1)!;
      }
    }

    final fallback = RegExp(
      r'\b([A-Z]{2,6})\b',
    ).allMatches(text).map((m) => m.group(1)!);
    for (final token in fallback) {
      if (token == 'BUY' ||
          token == 'SELL' ||
          token == 'GST' ||
          token == 'AUD') {
        continue;
      }
      return token;
    }
    return '';
  }

  String _extractSecurityName(String text, List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toUpperCase();
      if (line.contains('SECURITY') || line.contains('COMPANY')) {
        if (i + 1 < lines.length) {
          final value = lines[i + 1];
          if (!_looksLikeLabel(value)) {
            return value;
          }
        }
      }
    }
    return '';
  }

  InvestmentTransactionType _extractTransactionType(String text) {
    if (RegExp(r'\bSELL\b', caseSensitive: false).hasMatch(text)) {
      return InvestmentTransactionType.sell;
    }
    return InvestmentTransactionType.buy;
  }

  DateTime? _extractDate(String text, List<String> labels) {
    for (final label in labels) {
      final re = RegExp(
        '$label\\s*[:\\-]?\\s*(\\d{1,2}[\\/\\-]\\d{1,2}[\\/\\-]\\d{2,4}|\\d{4}[\\/\\-]\\d{1,2}[\\/\\-]\\d{1,2})',
        caseSensitive: false,
      );
      final m = re.firstMatch(text);
      if (m != null) {
        final d = parseFlexibleDate(m.group(1)!);
        if (d != null) return d;
      }
    }
    return null;
  }

  double? _extractMoneyLike(String text, List<String> labels) {
    for (final label in labels) {
      final re = RegExp(
        '${RegExp.escape(label)}[^\\d\\-]*(\\\$?\\s*[\\d,]+(?:\\.\\d+)?)',
        caseSensitive: false,
      );
      final m = re.firstMatch(text);
      if (m != null) {
        return parseMoney(m.group(1)!);
      }
    }
    return null;
  }

  String? _extractAfterLabel(String text, List<String> labels) {
    for (final label in labels) {
      final re = RegExp(
        '$label\\s*[:\\-]?\\s*([A-Z0-9\\-]+)',
        caseSensitive: false,
      );
      final m = re.firstMatch(text);
      if (m != null) {
        return m.group(1);
      }
    }
    return null;
  }

  bool _looksLikeLabel(String value) {
    final upper = value.toUpperCase();
    return upper.contains('DATE') ||
        upper.contains('COST') ||
        upper.contains('PRICE') ||
        upper.contains('ACCOUNT') ||
        upper.contains('CONFIRMATION');
  }

  double _confidence(int missingCount, int warningCount) {
    final penalty = (missingCount * 0.15) + (warningCount * 0.05);
    final score = 1.0 - penalty;
    if (score < 0) {
      return 0;
    }
    if (score > 1) {
      return 1;
    }
    return score;
  }
}
