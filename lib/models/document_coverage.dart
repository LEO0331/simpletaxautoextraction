import 'tax_decimal.dart';

class DocumentCoverage {
  final String? id;
  static const families = [
    'brokerTrade',
    'fundAnnual',
    'drpAdvice',
    'openingHoldings',
    'closingHoldings',
    'bankInterest',
    'rental',
    'dividend',
    'other',
  ];
  static const states = [
    'missing',
    'available',
    'reviewed',
    'insufficient',
    'notApplicable',
  ];
  final String userId,
      account,
      ticker,
      family,
      state,
      evidenceReference,
      sourceHash,
      linkedDomain,
      linkedRecordId,
      unitsExact,
      observationDateIso;
  final int taxYearStart, revision;
  final int? firstPage, lastPage;
  final bool required, isVoided;
  const DocumentCoverage({
    this.id,
    required this.userId,
    required this.taxYearStart,
    required this.account,
    required this.ticker,
    required this.family,
    this.state = 'missing',
    this.required = true,
    this.evidenceReference = '',
    this.sourceHash = '',
    this.firstPage,
    this.lastPage,
    this.linkedDomain = '',
    this.linkedRecordId = '',
    this.unitsExact = '',
    this.observationDateIso = '',
    this.revision = 0,
    this.isVoided = false,
  });
  List<String> validation() {
    final issues = <String>[];
    if (userId.isEmpty ||
        account.trim().isEmpty ||
        taxYearStart < 1900 ||
        taxYearStart > 2199 ||
        !families.contains(family) ||
        !states.contains(state)) {
      issues.add('Document identity or state is invalid.');
    }
    if (['reviewed', 'notApplicable'].contains(state) &&
        evidenceReference.trim().isEmpty) {
      issues.add('Reviewed evidence requires a source reference.');
    }
    if ((firstPage == null) != (lastPage == null) ||
        (firstPage != null && (firstPage! < 1 || lastPage! < firstPage!))) {
      issues.add('Select a valid source page range.');
    }
    if (sourceHash.isNotEmpty &&
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceHash)) {
      issues.add('Invalid source fingerprint.');
    }
    if (family.endsWith('Holdings') && state == 'reviewed') {
      try {
        if (TaxDecimal.parse(unitsExact).isNegative) {
          issues.add('Holdings cannot be negative.');
        }
      } catch (_) {
        issues.add('Enter exact observed units.');
      }
      if (parseDocumentDate(observationDateIso) == null) {
        issues.add('Enter a valid observation date.');
      }
    }
    return issues;
  }

  Map<String, dynamic> toMap() => {
    'schemaVersion': 1,
    'userId': userId,
    'taxYearStart': taxYearStart,
    'account': account,
    'ticker': ticker,
    'family': family,
    'state': state,
    'required': required,
    'evidenceReference': evidenceReference,
    'sourceHash': sourceHash,
    'firstPage': firstPage,
    'lastPage': lastPage,
    'linkedDomain': linkedDomain,
    'linkedRecordId': linkedRecordId,
    'unitsExact': unitsExact,
    'observationDateIso': observationDateIso,
    'revision': revision,
    'isVoided': isVoided,
  };
  factory DocumentCoverage.fromMap(Map<String, dynamic> m, {String? id}) =>
      DocumentCoverage(
        id: id,
        userId: m['userId'] as String,
        taxYearStart: m['taxYearStart'] as int,
        account: m['account'] as String,
        ticker: m['ticker'] as String,
        family: m['family'] as String,
        state: m['state'] as String,
        required: m['required'] as bool,
        evidenceReference: m['evidenceReference'] as String,
        sourceHash: m['sourceHash'] as String,
        firstPage: m['firstPage'] as int?,
        lastPage: m['lastPage'] as int?,
        linkedDomain: m['linkedDomain'] as String,
        linkedRecordId: m['linkedRecordId'] as String,
        unitsExact: m['unitsExact'] as String,
        observationDateIso: m['observationDateIso'] as String,
        revision: m['revision'] as int,
        isVoided: m['isVoided'] as bool,
      );
}

DateTime? parseDocumentDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final p = value.split('-').map(int.parse).toList();
  final d = DateTime.utc(p[0], p[1], p[2]);
  return d.year == p[0] && d.month == p[1] && d.day == p[2] ? d : null;
}

List<String> coverageIssues(List<DocumentCoverage> records) => [
  for (final r in records.where((r) => !r.isVoided && r.required)) ...[
    if (!['reviewed', 'notApplicable'].contains(r.state))
      '${r.family}: evidence for ${r.account}/${r.ticker} is ${r.state}.',
    ...r.validation(),
  ],
];

/// Each known source needs its own reviewed evidence. An account-level document
/// alone cannot establish completeness of an entire broker or fund history.
List<String> knownDocumentCoverageIssues(
  List<DocumentCoverage> coverage,
  List<Map<String, dynamic>> knownSources,
) {
  final reviewed = coverage.where(
    (r) => !r.isVoided && r.state == 'reviewed' && r.validation().isEmpty,
  );
  return [
    for (final source in knownSources)
      if (!reviewed.any((r) {
        if (r.account != source['account'] ||
            r.ticker != source['ticker'] ||
            r.family != source['family']) {
          return false;
        }
        if (source['id'] is String &&
            (source['id'] as String).isNotEmpty &&
            r.linkedRecordId == source['id'] &&
            r.linkedDomain == source['domain']) {
          return true;
        }
        if (source['sourceHash'] is! String ||
            (source['sourceHash'] as String).isEmpty ||
            r.sourceHash != source['sourceHash']) {
          return false;
        }
        final first = source['firstPage'], last = source['lastPage'];
        return first is int &&
            last is int &&
            r.firstPage != null &&
            r.lastPage != null &&
            r.firstPage! <= first &&
            r.lastPage! >= last;
      }))
        'Missing reviewed ${source['family']} evidence for ${source['account']}/${source['ticker']} record ${source['id']}.',
  ];
}
