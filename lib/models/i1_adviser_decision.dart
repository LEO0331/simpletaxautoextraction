import 'tax_decimal.dart';

/// An evidenced adviser determination. Coverage names every asset considered at
/// one departure event; a reference to an annual worksheet prevents this being
/// mistaken for a standalone deemed sale that removes investment units.
class I1AdviserDecision {
  final String decisionReference,
      scopeEvidence,
      annualWorksheetReference,
      gain,
      loss,
      discountFraction,
      ruleVersion;
  final List<String> coveredAssets;
  const I1AdviserDecision({
    required this.decisionReference,
    required this.coveredAssets,
    required this.scopeEvidence,
    required this.annualWorksheetReference,
    required this.gain,
    required this.loss,
    required this.discountFraction,
    required this.ruleVersion,
  });
  List<String> validation() {
    final issues = <String>[];
    try {
      final g = TaxDecimal.parse(gain), l = TaxDecimal.parse(loss);
      if (g.isNegative ||
          l.isNegative ||
          g != g.rounded() ||
          l != l.rounded() ||
          (!g.isZero && !l.isZero)) {
        issues.add(
          'Adviser gain/loss require nonnegative cents and cannot both be positive',
        );
      }
    } on FormatException {
      issues.add('Invalid adviser gain/loss amounts');
    }
    if (![
          decisionReference,
          scopeEvidence,
          annualWorksheetReference,
          ruleVersion,
        ].every((s) => s.trim().isNotEmpty && s.length <= 1000) ||
        !['0', '0.5'].contains(discountFraction) ||
        coveredAssets.isEmpty ||
        coveredAssets.any((s) => s.trim().isEmpty || s.length > 1000) ||
        coveredAssets.toSet().length != coveredAssets.length) {
      issues.add(
        'Adviser decision needs complete asset scope, rule version and annual worksheet evidence',
      );
    }
    return issues;
  }

  Map<String, dynamic> toMap() => {
    'decisionReference': decisionReference,
    'coveredAssets': coveredAssets,
    'scopeEvidence': scopeEvidence,
    'annualWorksheetReference': annualWorksheetReference,
    'gain': gain,
    'loss': loss,
    'discountFraction': discountFraction,
    'ruleVersion': ruleVersion,
  };
  factory I1AdviserDecision.fromMap(Map<String, dynamic> m) {
    if (m.keys.any(
      (k) => !{
        'decisionReference',
        'coveredAssets',
        'scopeEvidence',
        'annualWorksheetReference',
        'gain',
        'loss',
        'discountFraction',
        'ruleVersion',
      }.contains(k),
    )) {
      throw const FormatException('Unknown I1 adviser decision field');
    }
    return I1AdviserDecision(
      decisionReference: m['decisionReference'] as String,
      coveredAssets: List<String>.from(m['coveredAssets'] as List),
      scopeEvidence: m['scopeEvidence'] as String,
      annualWorksheetReference: m['annualWorksheetReference'] as String,
      gain: m['gain'] as String,
      loss: m['loss'] as String,
      discountFraction: m['discountFraction'] as String,
      ruleVersion: m['ruleVersion'] as String,
    );
  }
}
