import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:simpletaxautoextraction/services/managed_fund_pdf_service.dart';
import 'package:simpletaxautoextraction/models/tax_decimal.dart';

void main() {
  final path = Platform.environment['MANAGED_FUND_SAMPLE_PDF_PATH'];
  test('Private combined sample has separately reviewable AMMA pages', () async {
    final bytes = await File(path!).readAsBytes();
    final expectationsPath =
        Platform.environment['MANAGED_FUND_EXPECTATIONS_PATH'];
    var expectations = <String, dynamic>{};
    if (expectationsPath != null) {
      try {
        expectations =
            jsonDecode(await File(expectationsPath).readAsString())
                as Map<String, dynamic>;
      } catch (_) {
        fail('Private expectation file is unavailable or invalid.');
      }
    }
    final ranges = (Platform.environment['MANAGED_FUND_SAMPLE_PAGES'] ?? '1-2')
        .split(',')
        .map((value) {
          final parts = value.split('-');
          return (int.parse(parts.first), int.parse(parts.last));
        });
    for (final range in ranges) {
      final result = await ManagedFundPdfService().extract(
        bytes,
        userId: 'local-review',
        firstPage: range.$1,
        lastPage: range.$2,
      );
      // Never let a failed assertion expose source amounts or account data.
      expect(result.draft.isReviewed, isFalse);
      expect(
        result.draft.issuer.isNotEmpty,
        isTrue,
        reason:
            'Issuer adapter not recognized at pages ${range.$1}-${range.$2}',
      );
      expect(
        result.draft.components['grossCapitalGain']!.isNotEmpty,
        isTrue,
        reason: 'Gross gain field unavailable at selected pages',
      );
      expect(
        result.draft.components['amitShortfall']!.isNotEmpty ||
            result.missingFields.contains('amitShortfall'),
        isTrue,
        reason: 'Shortfall field unavailable at selected pages',
      );
      expect(
        result.draft.components['amitExcess']!.isNotEmpty ||
            result.missingFields.contains('amitExcess'),
        isTrue,
        reason: 'Excess field unavailable at selected pages',
      );
      expect(result.draft.sourceReference.startsWith('sha256:'), isTrue);
      final expected = expectations['${range.$1}'] as Map?;
      if (expected != null) {
        for (final entry in expected.entries) {
          final actual = result.draft.components[entry.key] ?? '';
          if (actual.isEmpty) {
            expect(result.missingFields.contains(entry.key), isTrue);
            continue;
          }
          var matches = false;
          try {
            matches =
                actual.isNotEmpty &&
                TaxDecimal.parse(actual) ==
                    TaxDecimal.parse(entry.value as String);
          } catch (_) {
            // FormatException carries its source string; never expose it.
          }
          expect(
            matches,
            isTrue,
            reason:
                'Independent value reconciliation failed for ${entry.key} on page ${range.$1}',
          );
        }
      }
    }
  }, skip: path == null ? 'Private sample path not configured' : false);
}
