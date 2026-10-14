import '../../models/managed_fund_statement.dart';
import '../../models/tax_decimal.dart';

class FundPdfAmount {
  final String value;
  final double column;
  const FundPdfAmount(this.value, this.column);
}

class FundPdfRow {
  final int page;
  final String label;
  final List<FundPdfAmount> amounts;
  const FundPdfRow(this.page, this.label, this.amounts);
}

class ManagedFundExtractionResult {
  final ManagedFundStatement draft;
  final List<String> warnings, missingFields;
  final Map<String, String> fieldEvidence;
  final String sourceHash;
  const ManagedFundExtractionResult({
    required this.draft,
    required this.warnings,
    required this.missingFields,
    required this.fieldEvidence,
    this.sourceHash = '',
  });
}

/// Narrow, review-only adapters for observed iShares and Betashares AMMA tables.
/// Raw source text is transient. Evidence contains field names/page numbers only.
class ManagedFundStatementParser {
  static const version = 'amma-spatial-v1';
  ManagedFundExtractionResult parse(
    List<FundPdfRow> rows, {
    required String userId,
    required String sourceHash,
  }) {
    final text = rows.map((r) => r.label).join('\n');
    final lower = text.toLowerCase();
    final warnings = <String>[
      'Check every extracted amount against the original statement. Missing fields are blank, not zero.',
      'Annual AMIT amounts do not assign parcel adjustments or create DRP acquisitions.',
    ];
    final evidence = <String, String>{};
    final components = <String, String>{
      for (final key in ManagedFundStatement.componentKeys) key: '',
    };
    final issuer = lower.contains('ishares') && lower.contains('betashares')
        ? ''
        : lower.contains('ishares')
        ? 'iShares'
        : lower.contains('betashares')
        ? 'Betashares'
        : '';
    final titles = rows
        .where(
          (r) => RegExp(
            r'attribution managed investment trust member annual (?:tax )?statement',
            caseSensitive: false,
          ).hasMatch(r.label),
        )
        .length;
    final supported =
        issuer.isNotEmpty &&
        titles == 1 &&
        lower.contains('part a') &&
        lower.contains('part b') &&
        !RegExp(
          r'reference pack|private master|table of contents',
          caseSensitive: false,
        ).hasMatch(text);
    final years = RegExp(
      r'year ended\s+30\s+june\s+(20\d{2})',
      caseSensitive: false,
    ).allMatches(text).map((m) => int.parse(m[1]!) - 1).toSet();
    // Some issuer headers use a compact reporting-period line.
    if (years.isEmpty) {
      years.addAll(
        RegExp(
              r'(?:financial year|tax year)\s*:?\s*(20\d{2})\s*[-/]\s*(20\d{2}|\d{2})',
              caseSensitive: false,
            )
            .allMatches(text)
            .where((m) {
              final start = int.parse(m[1]!);
              final end = int.parse(m[2]!.length == 2 ? '20${m[2]}' : m[2]!);
              return end == start + 1;
            })
            .map((m) => int.parse(m[1]!)),
      );
    }
    String uniqueIdentity(String pattern) {
      final values = RegExp(
        pattern,
        caseSensitive: false,
      ).allMatches(text).map((m) => m[1]!.trim()).toSet();
      return values.length == 1 ? values.single : '';
    }

    final ticker = uniqueIdentity(
      r'(?:ASX code|ASX ticker|ticker)\s*:?\s*([A-Z][A-Z0-9]{1,9})\b',
    );
    final account = uniqueIdentity(
      r'(?:account number|holder number|investor number)\s*:?\s*([A-Z0-9-]{3,64})\b',
    );
    void setField(String key, List<FundPdfRow> matches, {bool halve = false}) {
      final values = <String>{};
      final pages = <int>{};
      for (final row in matches) {
        // Observed attribution/summary columns are on the right. Never use a
        // cash or offset value when the attribution cell itself is empty.
        final amounts = row.amounts.where((a) => a.column > .78).toList();
        if (amounts.length != 1) continue;
        try {
          var value = TaxDecimal.parse(amounts.single.value);
          if (value.isNegative || value != value.rounded()) continue;
          if (halve) value = value * TaxDecimal.parse('0.5');
          if (value != value.rounded()) continue;
          values.add(value.toString());
          pages.add(row.page);
        } on FormatException {
          continue;
        }
      }
      if (values.length == 1) {
        components[key] = values.single;
        evidence[key] =
            'Pages ${pages.join(', ')}: $key${halve ? ' (grossed component divided by two)' : ''}';
      } else if (values.length > 1) {
        warnings.add(
          'Conflicting repeated $key fields. Enter the verified amount manually.',
        );
      }
    }

    List<FundPdfRow> matching(String pattern) => rows
        .where((r) => RegExp(pattern, caseSensitive: false).hasMatch(r.label))
        .toList();
    if (supported) {
      setField(
        'grossCapitalGain',
        matching(r'^total current year capital gains(?:\s+18h)?\s*$'),
      );
      setField(
        'foreignIncome',
        matching(r'^assessable foreign source income(?:\s+20e)?\s*$'),
      );
      setField(
        'frankingCredits',
        matching(
          r'^(?:share of franking credits|franking credits|franking credit tax offset from australian resident companies)(?:\s+13q)?\s*$',
        ),
      );
      setField(
        'foreignTaxOffset',
        matching(r'^foreign income tax offset\*?(?:\s+20o)?\s*$'),
      );
      setField(
        'cashDistributions',
        matching(r'^gross (?:cash distribution|amount)\s*$'),
      );
      setField(
        'amitShortfall',
        matching(
          r'^amit cost base net amount\s*-\s*shortfall\s*\((?:increase cost base|increase)\)\s*$',
        ),
      );
      setField(
        'amitExcess',
        matching(
          r'^amit cost base net amount\s*-\s*excess\s*\((?:reduce cost base|decrease cost base|decrease)\)\s*$',
        ),
      );
      setField('australianIncome', matching(r'^total australian income\s*$'));
      setField(
        'withholding',
        matching(
          r'^(?:tax withheld|total tax withheld|tax file number withholding tax)(?:\s+13r)?\s*$',
        ),
      );
      if (issuer == 'Betashares') {
        // The item-18 additional-information total is already grossed up.
        // Detailed TAP/NTAP rows are not additional gains to add to this total.
        setField(
          'discountedCapitalGain',
          matching(
            r'^capital gains\s*-\s*discounted method(?:\s*\(grossed up amount\))?\s*$',
          ),
          halve: true,
        );
        setField(
          'otherCapitalGain',
          matching(r'^capital gains\s*-\s*other method\s*$'),
        );
      } else {
        void sumComponents(String key, String pattern) {
          final matches = matching(pattern);
          final groups = <String, List<FundPdfRow>>{};
          for (final row in matches) {
            groups.putIfAbsent(row.label.toLowerCase(), () => []).add(row);
          }
          if (groups.isEmpty) return;
          var sum = TaxDecimal.zero;
          for (final group in groups.values) {
            final values = <String>{};
            for (final row in group) {
              final cells = row.amounts.where((a) => a.column > .78).toList();
              if (cells.length == 1) values.add(cells.single.value);
            }
            if (values.length != 1) return;
            try {
              final value = TaxDecimal.parse(values.single);
              if (value.isNegative || value != value.rounded()) return;
              sum += value;
            } on FormatException {
              return;
            }
          }
          components[key] = sum.toString();
          evidence[key] =
              'Pages ${matches.map((r) => r.page).toSet().join(', ')}: distinct $key attribution rows summed once';
        }

        sumComponents(
          'discountedCapitalGain',
          r'^discounted capital gains (?:tap|ntap)(?:\s*-\s*(?:clean building mit income|excluded from ncmi|ncmi))?\s*$',
        );
        sumComponents(
          'otherCapitalGain',
          r'^capital gains\s*-\s*other method (?:tap|ntap)(?:\s*-\s*(?:clean building mit income|excluded from ncmi|ncmi))?\s*$',
        );
      }
      if ([
        'discountedCapitalGain',
        'otherCapitalGain',
        'grossCapitalGain',
      ].every((k) => components[k]!.isNotEmpty)) {
        if (TaxDecimal.parse(components['grossCapitalGain']!) !=
            TaxDecimal.parse(components['discountedCapitalGain']!) *
                    TaxDecimal.parse('2') +
                TaxDecimal.parse(components['otherCapitalGain']!)) {
          warnings.add(
            'Capital gains do not reconcile. Check gross-up and unsupported components before saving.',
          );
        }
      }
    } else {
      warnings.add(
        'Select one complete supported AMMA statement, including summary and component pages. Guides, combined statements and unknown layouts require manual entry.',
      );
    }
    final missing = <String>[
      if (!supported || ticker.isEmpty) 'ticker',
      if (!supported || account.isEmpty) 'accountNumber',
      if (!supported || years.length != 1) 'yearStart',
      if (!supported || issuer.isEmpty) 'issuer',
      for (final e in components.entries)
        if (e.value.isEmpty) e.key,
    ];
    return ManagedFundExtractionResult(
      draft: ManagedFundStatement(
        id: null,
        userId: userId,
        ticker: supported ? ticker : '',
        accountNumber: supported ? account : '',
        issuer: supported ? issuer : '',
        layoutVersion:
            '$version-${supported ? issuer.toLowerCase() : 'manual'}',
        yearStart: supported && years.length == 1 ? years.single : 0,
        sourceReference:
            'sha256:$sourceHash;pages:${rows.map((r) => r.page).toSet().join(',')}',
        components: components,
      ),
      warnings: List.unmodifiable(warnings),
      missingFields: List.unmodifiable(missing),
      fieldEvidence: Map.unmodifiable(evidence),
      sourceHash: sourceHash,
    );
  }
}
