import 'managed_fund_statement.dart';
import 'tax_decimal.dart';

/// Reviewed same-owner, same-security split/consolidation without cash, scrip
/// rollover, demerger or fractional entitlement disposal. Basis is conserved.
class CorporateActionDecision {
  final String id,
      userId,
      date,
      parcelId,
      oldUnits,
      newUnits,
      evidenceReference;
  final int revision;
  final bool reviewed, isVoided;
  const CorporateActionDecision({
    required this.id,
    required this.userId,
    required this.date,
    required this.parcelId,
    required this.oldUnits,
    required this.newUnits,
    required this.evidenceReference,
    this.revision = 0,
    this.reviewed = false,
    this.isVoided = false,
  });
  List<String> validation() {
    final issues = <String>[];
    try {
      parseFundDate(date);
      if ([
            id,
            userId,
            parcelId,
            evidenceReference,
          ].any((v) => v.trim().isEmpty) ||
          TaxDecimal.parse(oldUnits) <= TaxDecimal.zero ||
          TaxDecimal.parse(newUnits) <= TaxDecimal.zero ||
          revision < 0) {
        issues.add(
          'Split requires positive evidenced units and source identity',
        );
      }
    } on FormatException {
      issues.add('Invalid split date or units');
    }
    if (!reviewed) issues.add('Split/consolidation requires review');
    return issues;
  }

  Map<String, dynamic> toMap() => {
    'schemaVersion': 1,
    'type': 'split',
    'userId': userId,
    'date': date,
    'parcelId': parcelId,
    'oldUnits': oldUnits,
    'newUnits': newUnits,
    'evidenceReference': evidenceReference,
    'revision': revision,
    'reviewed': reviewed,
    'isVoided': isVoided,
  };
  factory CorporateActionDecision.fromMap(
    Map<String, dynamic> m, {
    required String id,
  }) => CorporateActionDecision(
    id: id,
    userId: m['userId'] as String,
    date: m['date'] as String,
    parcelId: m['parcelId'] as String,
    oldUnits: m['oldUnits'] as String,
    newUnits: m['newUnits'] as String,
    evidenceReference: m['evidenceReference'] as String,
    revision: m['revision'] as int? ?? 0,
    reviewed: m['reviewed'] == true,
    isVoided: m['isVoided'] == true,
  );
}
