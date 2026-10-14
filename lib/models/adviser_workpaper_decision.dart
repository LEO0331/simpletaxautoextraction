import 'tax_decimal.dart';
import 'tax_workspace.dart' show taxWorkspaceTotals;

class AdviserClosingLossBalance {
  final int originStartYear;
  final String amount, evidenceReference;
  const AdviserClosingLossBalance({
    required this.originStartYear,
    required this.amount,
    required this.evidenceReference,
  });
  Map<String, dynamic> toMap() => {
    'originStartYear': originStartYear,
    'amount': amount,
    'evidenceReference': evidenceReference,
  };
  factory AdviserClosingLossBalance.fromMap(Map<String, dynamic> map) =>
      AdviserClosingLossBalance(
        originStartYear: map['originStartYear'] as int,
        amount: map['amount'] as String,
        evidenceReference: map['evidenceReference'] as String,
      );
}

/// Complete annual totals supplied by an adviser, never an automatic tax rule.
/// All categories replace the base report once; closing losses remain separately
/// evidenced and are not income or additional reductions of net capital gain.
class AdviserWorkpaperDecision {
  final int yearStart;
  final String sourceFingerprint,
      adviserReference,
      evidenceReference,
      ruleVersion;
  final Map<String, String> totals;
  final List<AdviserClosingLossBalance> closingLossBalances;
  final List<String> legalIssuesCovered;
  final bool reviewed, completeSources;
  AdviserWorkpaperDecision({
    required this.yearStart,
    required this.sourceFingerprint,
    required this.adviserReference,
    required this.evidenceReference,
    required this.ruleVersion,
    required Map<String, String> totals,
    List<AdviserClosingLossBalance> closingLossBalances = const [],
    List<String> legalIssuesCovered = const [],
    this.reviewed = false,
    this.completeSources = false,
  }) : totals = Map.unmodifiable(totals),
       closingLossBalances = List.unmodifiable(closingLossBalances),
       legalIssuesCovered = List.unmodifiable(legalIssuesCovered);

  List<String> validation() {
    final issues = <String>[];
    if (yearStart < 1900 ||
        yearStart > 2199 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceFingerprint) ||
        [
          adviserReference,
          evidenceReference,
          ruleVersion,
        ].any((v) => v.trim().isEmpty || v.length > 1000)) {
      issues.add(
        'Adviser workpaper needs year, current source fingerprint, adviser, evidence and rule version',
      );
    }
    if (totals.length != taxWorkspaceTotals.length ||
        !taxWorkspaceTotals.every(totals.containsKey)) {
      issues.add(
        'Adviser workpaper must supply every annual category exactly once',
      );
    }
    for (final entry in totals.entries) {
      try {
        final value = TaxDecimal.parse(entry.value);
        if (!taxWorkspaceTotals.contains(entry.key) ||
            (entry.key != 'rentalNet' && value.isNegative) ||
            (entry.key != 'netCapitalGain' && value != value.rounded())) {
          issues.add('Invalid adviser total for ${entry.key}');
        }
      } on FormatException {
        issues.add('Invalid adviser total for ${entry.key}');
      }
    }
    final years = <int>{};
    for (final balance in closingLossBalances) {
      try {
        final amount = TaxDecimal.parse(balance.amount);
        if (balance.originStartYear < 1900 ||
            balance.originStartYear > yearStart ||
            !years.add(balance.originStartYear) ||
            amount <= TaxDecimal.zero ||
            amount != amount.rounded() ||
            balance.evidenceReference.trim().isEmpty ||
            balance.evidenceReference.length > 1000) {
          issues.add(
            'Closing capital losses require unique originating years and evidenced positive cents',
          );
        }
      } on FormatException {
        issues.add('Invalid closing capital loss');
      }
    }
    if (legalIssuesCovered.toSet().length != legalIssuesCovered.length ||
        legalIssuesCovered.any(
          (issue) => issue.isEmpty || issue.length > 1000,
        )) {
      issues.add('Repeated or invalid adviser legal scope');
    }
    if (!reviewed || !completeSources) {
      issues.add(
        'Adviser workpaper requires review and complete source coverage',
      );
    }
    return issues;
  }

  Map<String, dynamic> toMap() => {
    'schemaVersion': 1,
    'yearStart': yearStart,
    'sourceFingerprint': sourceFingerprint,
    'adviserReference': adviserReference,
    'evidenceReference': evidenceReference,
    'ruleVersion': ruleVersion,
    'totals': totals,
    'closingLossBalances': closingLossBalances.map((b) => b.toMap()).toList(),
    'legalIssuesCovered': legalIssuesCovered,
    'reviewed': reviewed,
    'completeSources': completeSources,
  };
  factory AdviserWorkpaperDecision.fromMap(Map<String, dynamic> map) {
    const keys = {
      'schemaVersion',
      'yearStart',
      'sourceFingerprint',
      'adviserReference',
      'evidenceReference',
      'ruleVersion',
      'totals',
      'closingLossBalances',
      'legalIssuesCovered',
      'reviewed',
      'completeSources',
    };
    if (map['schemaVersion'] != 1 || map.keys.any((k) => !keys.contains(k))) {
      throw const FormatException('Unknown adviser workpaper schema');
    }
    return AdviserWorkpaperDecision(
      yearStart: map['yearStart'] as int,
      sourceFingerprint: map['sourceFingerprint'] as String,
      adviserReference: map['adviserReference'] as String,
      evidenceReference: map['evidenceReference'] as String,
      ruleVersion: map['ruleVersion'] as String,
      totals: Map<String, String>.from(map['totals'] as Map),
      closingLossBalances: (map['closingLossBalances'] as List)
          .map(
            (b) => AdviserClosingLossBalance.fromMap(
              Map<String, dynamic>.from(b as Map),
            ),
          )
          .toList(),
      legalIssuesCovered: List<String>.from(map['legalIssuesCovered'] as List),
      reviewed: map['reviewed'] == true,
      completeSources: map['completeSources'] == true,
    );
  }
}
