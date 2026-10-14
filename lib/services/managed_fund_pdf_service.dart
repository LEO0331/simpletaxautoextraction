import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../utils/source_fingerprint.dart';
import 'parsers/managed_fund_statement_parser.dart';

class ManagedFundPdfService {
  Future<ManagedFundExtractionResult> extract(
    List<int> bytes, {
    required String userId,
    int? firstPage,
    int? lastPage,
  }) async {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('Choose a readable PDF smaller than 10 MB.');
    }
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      final start = firstPage ?? 1, end = lastPage ?? document.pages.count;
      if (start < 1 ||
          end < start ||
          end > document.pages.count ||
          end - start >= 5) {
        throw const FormatException(
          'Select one statement using up to five valid PDF pages.',
        );
      }
      final extractor = PdfTextExtractor(document);
      final rows = <FundPdfRow>[];
      for (var page = start; page <= end; page++) {
        final words =
            extractor
                .extractTextLines(
                  startPageIndex: page - 1,
                  endPageIndex: page - 1,
                )
                .expand((line) => line.wordCollection)
                .toList()
              ..sort((a, b) {
                final y = a.bounds.center.dy.compareTo(b.bounds.center.dy);
                return y != 0 ? y : a.bounds.left.compareTo(b.bounds.left);
              });
        final groups = <List<TextWord>>[];
        for (final word in words) {
          if (groups.isEmpty ||
              (groups.last.first.bounds.center.dy - word.bounds.center.dy)
                      .abs() >
                  2) {
            groups.add([word]);
          } else {
            groups.last.add(word);
          }
        }
        final width = document.pages[page - 1].size.width;
        for (final group in groups) {
          group.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
          final labels = <String>[], amounts = <FundPdfAmount>[];
          for (final word in group) {
            final rawToken = word.text.trim();
            final token = word.text
                .replaceAll(',', '')
                .replaceAll(r'$', '')
                .trim();
            if (RegExp(
              r'^\$?-?(?:\d+|\d{1,3}(?:,\d{3})+)\.\d{2}$',
            ).hasMatch(rawToken)) {
              amounts.add(FundPdfAmount(token, word.bounds.center.dx / width));
            } else if (word.text.trim() != r'$') {
              labels.add(word.text);
            }
          }
          rows.add(
            FundPdfRow(
              page,
              labels
                  .join(' ')
                  .replaceAll(RegExp('[\u2013\u2014\u00b1]'), '-')
                  .replaceAll('\\', '')
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim(),
              amounts,
            ),
          );
        }
      }
      return ManagedFundStatementParser().parse(
        rows,
        userId: userId,
        sourceHash: SourceFingerprint.sha256(bytes),
      );
    } catch (_) {
      throw const FormatException(
        'Unsupported or unreadable PDF. Enter the statement manually.',
      );
    } finally {
      document?.dispose();
    }
  }
}
