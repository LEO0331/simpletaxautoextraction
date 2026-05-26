# PDF Parsing Harness

Source: The app depends on client-side parsing for property statements and CommSec-style trade confirmations.
Trigger: Read when editing `PdfExtractionService`, parser helpers, parser tests, file upload flows, or parser fixtures.
Expiry: Revise when parsing moves server-side or when parsers are split into packages.

## Parser Boundaries

Property worksheet PDFs:
- Top-level service: `lib/services/pdf_extraction_service.dart`
- Output model: `TaxRecord`
- Supported layouts: Forge Real Estate and generic property statement patterns.

Investment PDFs:
- Parser: `lib/services/parsers/commsec_trade_confirmation_parser.dart`
- Output draft/result: `InvestmentTransactionDraft` and `InvestmentExtractionResult`
- Expected source: CommSec-style trade confirmation PDF text extraction.

## Privacy Constraints

- Never commit real user PDFs or broker confirmations.
- Keep local sample PDF paths outside git.
- Redact raw extracted text in logs, screenshots, and reports.
- Do not print account numbers, confirmation numbers, or addresses from real documents.

## Parser Design Rules

- Prefer regex and fallback heuristics over brittle positional-only parsing.
- Missing or low-confidence fields should produce a reviewable draft, not silently incorrect records.
- Review screens must let the user correct extracted values before saving.
- Parser tests should use synthetic text fixtures unless explicitly gated by an environment variable.

## Verification

Run parser tests after parser changes:

```bash
flutter test test/extraction_service_test.dart
flutter test test/pdf_parsing_test.dart
flutter test test/services/pdf_extraction_service_metadata_test.dart
flutter test test/services/commsec_trade_confirmation_parser_test.dart
```

Optional local real-PDF check:

```bash
COMMSEC_SAMPLE_PDF_PATH=/absolute/private/path.pdf flutter test test/integration/commsec_sample_pdf_integration_test.dart
```

The real PDF must remain outside git.
