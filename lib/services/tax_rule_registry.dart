/// Versioned coverage of ordinary resident individual investment worksheets.
/// Year start 2025 denotes 1 July 2025 to 30 June 2026. Later reforms are
/// deliberately outside this registry, rather than inheriting a timeless rate.
class TaxRuleRegistry {
  static const supportedYearStarts = [2020, 2021, 2022, 2023, 2024, 2025];
  static bool supports(int yearStart) =>
      supportedYearStarts.contains(yearStart);
  static String version(int yearStart) => supports(yearStart)
      ? 'AU-individual-resident-$yearStart-${yearStart + 1}-v1'
      : 'unsupported-$yearStart';
  static const sources = [
    'https://www.legislation.gov.au/C2004A05138/2025-04-01/2025-04-01/text/original/epub/OEBPS/document_3/document_3.html',
    'https://www.ato.gov.au/forms-and-instructions/capital-gain-or-loss-worksheet-instructions',
  ];
}
