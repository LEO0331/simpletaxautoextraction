final _formulaPrefix = RegExp(r"^(?:[\x00-\x1f\x7f]|[\s']*[=+@＝＋＠－−-])");

/// Quotes text for CSV and keeps formula-like values as literal text when a
/// spreadsheet opens or re-saves the file.
String csvTextCell(String value) {
  // A visible prefix stays in the cell when a spreadsheet re-exports the CSV.
  final text = _formulaPrefix.hasMatch(value) ? '[text] $value' : value;
  return '"${text.replaceAll('"', '""')}"';
}
