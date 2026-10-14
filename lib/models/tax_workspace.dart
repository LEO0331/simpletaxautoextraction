import 'dart:convert';

import '../utils/source_fingerprint.dart';
import 'tax_decimal.dart';
import 'tax_record.dart';
import 'i1_adviser_decision.dart';

const taxWorkspaceSections = [
  'salary',
  'interest',
  'dividends',
  'funds',
  'rental',
  'capitalGains',
  'otherIncome',
  'deductions',
  'offsets',
];
const taxWorkspaceStates = [
  'notStarted',
  'documentsMissing',
  'imported',
  'needsReview',
  'reconciled',
  'notApplicable',
];
const taxWorkspaceTotals = [
  'salaryIncome',
  'interestIncome',
  'dividendIncome',
  'fundAustralianIncome',
  'fundForeignIncome',
  'rentalIncome',
  'rentalDeductions',
  'rentalNet',
  'netCapitalGain',
  'otherIncome',
  'deductions',
  'frankingCredits',
  'foreignTaxOffset',
  'otherOffsets',
  'withholding',
];

void _workspaceKeys(Map<String, dynamic> map, Set<String> keys) {
  if (map.keys.any((key) => !keys.contains(key))) {
    throw const FormatException('Unknown workspace schema field');
  }
}

DateTime workspaceDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Use YYYY-MM-DD dates');
  }
  final date = DateTime.tryParse('${value}T00:00:00Z');
  if (date == null || date.toIso8601String().substring(0, 10) != value) {
    throw const FormatException('Invalid calendar date');
  }
  return date;
}

bool workspaceMoney(String value, {bool signed = false}) {
  if (value.length > 100) {
    return false;
  }
  try {
    final n = TaxDecimal.parse(value);
    return (signed || !n.isNegative) && n == n.rounded();
  } on FormatException {
    return false;
  }
}

class ResidencyPeriod {
  final String start, endExclusive, classification, evidence;
  final bool reviewed;
  const ResidencyPeriod({
    required this.start,
    required this.endExclusive,
    required this.classification,
    required this.evidence,
    this.reviewed = false,
  });
  Map<String, dynamic> toMap() => {
    'start': start,
    'endExclusive': endExclusive,
    'classification': classification,
    'evidence': evidence,
    'reviewed': reviewed,
  };
  factory ResidencyPeriod.fromMap(Map<String, dynamic> m) {
    _workspaceKeys(m, {
      'start',
      'endExclusive',
      'classification',
      'evidence',
      'reviewed',
    });
    return ResidencyPeriod(
      start: m['start'] as String,
      endExclusive: m['endExclusive'] as String,
      classification: m['classification'] as String,
      evidence: m['evidence'] as String,
      reviewed: m['reviewed'] == true,
    );
  }
  List<String> validation() {
    final issues = <String>[];
    try {
      if (!workspaceDate(start).isBefore(workspaceDate(endExclusive))) {
        issues.add('Residency interval must have a positive duration');
      }
    } on FormatException catch (e) {
      issues.add(e.message);
    }
    if (![
          'resident',
          'foreign',
          'temporary',
          'unknown',
        ].contains(classification) ||
        evidence.length > 1000 ||
        (reviewed && evidence.trim().isEmpty)) {
      issues.add('Residency classification and review evidence are required');
    }
    return issues;
  }
}

class I1Review {
  final I1AdviserDecision? adviserDecision;
  final String date,
      assetReference,
      marketValue,
      costBase,
      reducedCostBase,
      classification,
      election,
      evidence,
      adviserReference;
  final bool reviewed;
  const I1Review({
    this.adviserDecision,
    required this.date,
    required this.assetReference,
    this.marketValue = '0',
    this.costBase = '0',
    this.reducedCostBase = '0',
    this.classification = 'unknown',
    this.election = 'undecided',
    this.evidence = '',
    this.adviserReference = '',
    this.reviewed = false,
  });
  Map<String, dynamic> toMap() => {
    if (adviserDecision != null) 'adviserDecision': adviserDecision!.toMap(),
    'date': date,
    'assetReference': assetReference,
    'marketValue': marketValue,
    'costBase': costBase,
    'reducedCostBase': reducedCostBase,
    'classification': classification,
    'election': election,
    'evidence': evidence,
    'adviserReference': adviserReference,
    'reviewed': reviewed,
  };
  factory I1Review.fromMap(Map<String, dynamic> m) {
    _workspaceKeys(m, {
      'adviserDecision',
      'date',
      'assetReference',
      'marketValue',
      'costBase',
      'reducedCostBase',
      'classification',
      'election',
      'evidence',
      'adviserReference',
      'reviewed',
    });
    return I1Review(
      adviserDecision: m['adviserDecision'] == null
          ? null
          : I1AdviserDecision.fromMap(
              Map<String, dynamic>.from(m['adviserDecision'] as Map),
            ),
      date: m['date'] as String,
      assetReference: m['assetReference'] as String,
      marketValue: m['marketValue'] as String,
      costBase: m['costBase'] as String,
      reducedCostBase: m['reducedCostBase'] as String,
      classification: m['classification'] as String,
      election: m['election'] as String,
      evidence: m['evidence'] as String,
      adviserReference: m['adviserReference'] as String,
      reviewed: m['reviewed'] == true,
    );
  }
  List<String> validation() {
    final issues = <String>[...?adviserDecision?.validation()];
    try {
      workspaceDate(date);
    } on FormatException catch (e) {
      issues.add(e.message);
    }
    if (assetReference.trim().isEmpty ||
        ![
          'unknown',
          'nonTAP',
          'tapExcluded',
          'preCGT',
          'temporaryResident',
        ].contains(classification) ||
        !['undecided', 'recognise', 'deferAllEligible'].contains(election)) {
      issues.add('Invalid I1 asset classification or election');
    }
    if (![marketValue, costBase, reducedCostBase].every(workspaceMoney)) {
      issues.add('I1 amounts require nonnegative cents');
    }
    if ([
          assetReference,
          evidence,
          adviserReference,
        ].any((v) => v.length > 1000) ||
        (reviewed &&
            (evidence.trim().isEmpty || adviserReference.trim().isEmpty))) {
      issues.add('Reviewed I1 needs evidence and an adviser reference');
    }
    return issues;
  }
}

class TaxWorkspace {
  final int yearStart, revision;
  final String userId, status, amendmentReason, cgtSnapshotId;
  final Map<String, String> sectionStates, sectionEvidence, prefill;
  final List<ResidencyPeriod> residencyPeriods;
  final List<I1Review> i1Reviews;
  const TaxWorkspace({
    required this.yearStart,
    required this.userId,
    this.revision = 0,
    this.status = 'draft',
    this.amendmentReason = '',
    this.cgtSnapshotId = '',
    this.sectionStates = const {},
    this.sectionEvidence = const {},
    this.prefill = const {},
    this.residencyPeriods = const [],
    this.i1Reviews = const [],
  });
  TaxWorkspace copyWith({
    int? yearStart,
    int? revision,
    String? userId,
    String? status,
    String? amendmentReason,
    String? cgtSnapshotId,
    Map<String, String>? sectionStates,
    Map<String, String>? sectionEvidence,
    Map<String, String>? prefill,
    List<ResidencyPeriod>? residencyPeriods,
    List<I1Review>? i1Reviews,
  }) => TaxWorkspace(
    yearStart: yearStart ?? this.yearStart,
    userId: userId ?? this.userId,
    revision: revision ?? this.revision,
    status: status ?? this.status,
    amendmentReason: amendmentReason ?? this.amendmentReason,
    cgtSnapshotId: cgtSnapshotId ?? this.cgtSnapshotId,
    sectionStates: sectionStates ?? this.sectionStates,
    sectionEvidence: sectionEvidence ?? this.sectionEvidence,
    prefill: prefill ?? this.prefill,
    residencyPeriods: residencyPeriods ?? this.residencyPeriods,
    i1Reviews: i1Reviews ?? this.i1Reviews,
  );
  Map<String, dynamic> toMap() => {
    'schemaVersion': 1,
    'userId': userId,
    'yearStart': yearStart,
    'revision': revision,
    'status': status,
    'amendmentReason': amendmentReason,
    'cgtSnapshotId': cgtSnapshotId,
    'sectionStates': Map<String, String>.from(sectionStates),
    'sectionEvidence': Map<String, String>.from(sectionEvidence),
    'prefill': Map<String, String>.from(prefill),
    'residencyPeriods': residencyPeriods.map((v) => v.toMap()).toList(),
    'i1Reviews': i1Reviews.map((v) => v.toMap()).toList(),
  };
  factory TaxWorkspace.fromMap(Map<String, dynamic> m) {
    _workspaceKeys(m, {
      'schemaVersion',
      'userId',
      'yearStart',
      'revision',
      'status',
      'amendmentReason',
      'cgtSnapshotId',
      'sectionStates',
      'sectionEvidence',
      'prefill',
      'residencyPeriods',
      'i1Reviews',
      'id',
      'createdAt',
      'updatedAt',
    });
    if (m['schemaVersion'] != 1) {
      throw const FormatException('Unsupported workspace schema');
    }
    return TaxWorkspace(
      userId: m['userId'] as String,
      yearStart: m['yearStart'] as int,
      revision: m['revision'] as int,
      status: m['status'] as String,
      amendmentReason: m['amendmentReason'] as String,
      cgtSnapshotId: m['cgtSnapshotId'] as String,
      sectionStates: Map<String, String>.from(m['sectionStates'] as Map),
      sectionEvidence: Map<String, String>.from(m['sectionEvidence'] as Map),
      prefill: Map<String, String>.from(m['prefill'] as Map),
      residencyPeriods: (m['residencyPeriods'] as List)
          .map(
            (v) => ResidencyPeriod.fromMap(Map<String, dynamic>.from(v as Map)),
          )
          .toList(),
      i1Reviews: (m['i1Reviews'] as List)
          .map((v) => I1Review.fromMap(Map<String, dynamic>.from(v as Map)))
          .toList(),
    );
  }
  List<String> validation() => [
    if (userId.trim().isEmpty ||
        yearStart < 1900 ||
        yearStart > 2199 ||
        revision < 0 ||
        !['draft', 'finalised'].contains(status))
      'Invalid workspace identity or status',
    if (sectionStates.entries.any(
      (e) =>
          !taxWorkspaceSections.contains(e.key) ||
          !taxWorkspaceStates.contains(e.value),
    ))
      'Unknown section state',
    if (sectionEvidence.entries.any(
          (e) => !taxWorkspaceSections.contains(e.key) || e.value.length > 1000,
        ) ||
        amendmentReason.length > 1000 ||
        cgtSnapshotId.length > 1000)
      'Invalid workspace evidence',
    if (prefill.entries.any(
      (e) =>
          !taxWorkspaceTotals.contains(e.key) ||
          !workspaceMoney(e.value, signed: e.key == 'rentalNet'),
    ))
      'Invalid prefill amount',
    ...residencyPeriods.expand((p) => p.validation()),
    ...i1Reviews.expand((p) => p.validation()),
  ];
}

class TaxWorkspaceItem {
  final String? id;
  final String userId,
      category,
      sourceReference,
      amount,
      deductions,
      withholding,
      frankingCredits,
      taxOffset,
      rentalRecordId,
      rentalFingerprint,
      ownershipPercent;
  final int yearStart, revision;
  final bool isReviewed, isVoided;
  const TaxWorkspaceItem({
    this.id,
    required this.userId,
    required this.yearStart,
    required this.category,
    required this.sourceReference,
    this.amount = '0',
    this.deductions = '0',
    this.withholding = '0',
    this.frankingCredits = '0',
    this.taxOffset = '0',
    this.rentalRecordId = '',
    this.rentalFingerprint = '',
    this.ownershipPercent = '100',
    this.isReviewed = false,
    this.isVoided = false,
    this.revision = 0,
  });
  TaxWorkspaceItem copyWith({
    String? id,
    String? userId,
    int? yearStart,
    String? category,
    String? sourceReference,
    String? amount,
    String? deductions,
    String? withholding,
    String? frankingCredits,
    String? taxOffset,
    String? rentalRecordId,
    String? rentalFingerprint,
    String? ownershipPercent,
    bool? isReviewed,
    bool? isVoided,
    int? revision,
  }) => TaxWorkspaceItem(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    yearStart: yearStart ?? this.yearStart,
    category: category ?? this.category,
    sourceReference: sourceReference ?? this.sourceReference,
    amount: amount ?? this.amount,
    deductions: deductions ?? this.deductions,
    withholding: withholding ?? this.withholding,
    frankingCredits: frankingCredits ?? this.frankingCredits,
    taxOffset: taxOffset ?? this.taxOffset,
    rentalRecordId: rentalRecordId ?? this.rentalRecordId,
    rentalFingerprint: rentalFingerprint ?? this.rentalFingerprint,
    ownershipPercent: ownershipPercent ?? this.ownershipPercent,
    isReviewed: isReviewed ?? this.isReviewed,
    isVoided: isVoided ?? this.isVoided,
    revision: revision ?? this.revision,
  );
  Map<String, dynamic> toMap() => {
    'schemaVersion': 1,
    'userId': userId,
    'yearStart': yearStart,
    'category': category,
    'sourceReference': sourceReference,
    'amount': amount,
    'deductions': deductions,
    'withholding': withholding,
    'frankingCredits': frankingCredits,
    'taxOffset': taxOffset,
    'rentalRecordId': rentalRecordId,
    'rentalFingerprint': rentalFingerprint,
    'ownershipPercent': ownershipPercent,
    'isReviewed': isReviewed,
    'isVoided': isVoided,
    'revision': revision,
  };
  factory TaxWorkspaceItem.fromMap(Map<String, dynamic> m, {String? id}) {
    _workspaceKeys(m, {
      'schemaVersion',
      'userId',
      'yearStart',
      'category',
      'sourceReference',
      'amount',
      'deductions',
      'withholding',
      'frankingCredits',
      'taxOffset',
      'rentalRecordId',
      'rentalFingerprint',
      'ownershipPercent',
      'isReviewed',
      'isVoided',
      'revision',
      'id',
      'createdAt',
      'updatedAt',
    });
    if (m['schemaVersion'] != 1) {
      throw const FormatException('Unsupported item schema');
    }
    return TaxWorkspaceItem(
      id: id ?? m['id'] as String?,
      userId: m['userId'] as String,
      yearStart: m['yearStart'] as int,
      category: m['category'] as String,
      sourceReference: m['sourceReference'] as String,
      amount: m['amount'] as String,
      deductions: m['deductions'] as String,
      withholding: m['withholding'] as String,
      frankingCredits: m['frankingCredits'] as String,
      taxOffset: m['taxOffset'] as String,
      rentalRecordId: m['rentalRecordId'] as String,
      rentalFingerprint: m['rentalFingerprint'] as String,
      ownershipPercent: m['ownershipPercent'] as String,
      isReviewed: m['isReviewed'] == true,
      isVoided: m['isVoided'] == true,
      revision: m['revision'] as int,
    );
  }
  List<String> validation() {
    final issues = <String>[];
    if (userId.trim().isEmpty ||
        sourceReference.trim().isEmpty ||
        sourceReference.length > 1000 ||
        yearStart < 1900 ||
        yearStart > 2199 ||
        revision < 0 ||
        ![
          'salary',
          'interest',
          'dividends',
          'otherIncome',
          'deductions',
          'offsets',
          'rentalReview',
        ].contains(category)) {
      issues.add('Invalid item identity, category or source');
    }
    if (![
      amount,
      deductions,
      withholding,
      frankingCredits,
      taxOffset,
    ].every(workspaceMoney)) {
      issues.add('Item amounts require nonnegative cents');
    }
    if (category == 'deductions' &&
        workspaceMoney(deductions) &&
        !TaxDecimal.parse(deductions).isZero) {
      issues.add(
        'Deduction items use amount only, without an ancillary deduction',
      );
    }
    if (category == 'offsets' &&
        workspaceMoney(taxOffset) &&
        !TaxDecimal.parse(taxOffset).isZero) {
      issues.add('Offset items use amount only, without an ancillary offset');
    }
    try {
      final share = TaxDecimal.parse(ownershipPercent);
      if (share <= TaxDecimal.zero || share > TaxDecimal.parse('100')) {
        issues.add('Ownership must be greater than zero and at most 100');
      }
    } on FormatException {
      issues.add('Invalid ownership percentage');
    }
    if (category == 'rentalReview' &&
        (rentalRecordId.isEmpty ||
            rentalFingerprint.isEmpty ||
            ![
              amount,
              deductions,
              withholding,
              frankingCredits,
              taxOffset,
            ].every((v) => workspaceMoney(v) && TaxDecimal.parse(v).isZero))) {
      issues.add(
        'Rental review requires a linked fingerprint and no duplicate manually entered amounts',
      );
    }
    return issues;
  }
}

String canonicalTaxFingerprint(Object? value) {
  Object? canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: canonical(v[k])};
    }
    if (v is List) return v.map(canonical).toList();
    if (v is DateTime) return v.toUtc().toIso8601String();
    if (v is double && !v.isFinite) {
      return {'invalidNonfiniteAmount': v.toString()};
    }
    return v;
  }

  return SourceFingerprint.text(jsonEncode(canonical(value)));
}

String taxRecordFingerprint(TaxRecord record) =>
    canonicalTaxFingerprint({'id': record.id, ...record.toMap()});
