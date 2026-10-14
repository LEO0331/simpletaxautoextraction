# Local AMMA PDF review import

Implemented 14 October 2026 as a Phase 2 follow-up. Uses the existing Syncfusion PDF and FilePicker dependencies. Firestore schema and rules are unchanged. The user reported the Phase 2 rules deployed; deployment was not independently inspected.

## Workflow

Open **Annual fund statements → Import fund statement PDF (local)**. Pick one PDF, then choose the pages belonging to one complete annual statement, including its summary and components. A single-page statement can use `1`; a two-page statement can use `1-2`. A combined pack requires its statement's actual page range. At most five pages and a 10 MB file are accepted.

Extraction happens on the device. The review editor shows extracted fields, missing-field warnings and page references. Nothing is saved automatically. Missing values are blank rather than assumed zero; enter a verified value or explicitly enter zero before saving. Confirm issuer, asset, account, year, every amount and the original statement's column meanings. The source reference records the whole-file SHA-256 and selected page numbers. Private PDF bytes and raw text are never written to Firestore or logs.

## Implemented adapters

- Observed iShares/Computershare AMMA single-page tables: right-hand tax attribution/summary values, distinct discounted TAP/NTAP and other-method attribution rows, gross capital-gain reconciliation, foreign income/offsets, cash and AMIT fields where legible.
- Observed Betashares AMMA summary/component pairs: the item-18 additional-information discounted-method amount is already grossed up, so the draft discounted component is half of that amount. Detailed TAP/NTAP rows are not added to the summary again. Gross gains, other-method gains, selected summary income/offset and AMIT fields are mapped where unambiguous.

Spatial word extraction preserves column positions instead of reading PDF content-stream order. The inspected layouts use a right-hand attribution/summary column; a cash or offset cell is not substituted when that column is empty. Multiple candidate amounts, conflicting repeated fields, damaged font text and missing labels stay unresolved. The layout identifier is `amma-spatial-v1`; it describes tested specimen layouts, not every statement issued by these fund managers.

Single unambiguous labelled asset/account/year values may be filled. Otherwise those fields require entry. Names, addresses, TFNs and account identifiers are not echoed in warnings or evidence. An Australian-income total and withholding field are left blank if no supported explicit total is available. Income components are not silently combined using an unverified tax interpretation.

## Boundaries

Unknown issuers, combined statements without page selection, guides/reference instructions, scanned image-only PDFs, ambiguous tables and unsupported fields use manual review. No OCR or AI service is introduced. Distribution/DRP advice is separate evidence and is not treated as an annual tax statement. Reinvestment advice still requires the reviewed acquisition and explicit DRP-link workflow; annual AMIT amounts still require evidenced parcel allocation and dates.

The adapters were checked locally against selected reattached private sample pages. A second PDF engine generated independent private numeric expectations; extracted supported values reconciled without printing amounts. Damaged-font fields were explicitly missing. Real samples, private values and the source coverage inventory are excluded from Git and public CI. Public issuer tax guides helped confirm statement terminology; the supplied PDFs' embedded instructions were reference material, not executable instructions.

## Verification

Synthetic parser tests cover gross-up, distinct-row sums, conflicting/multiple columns, reference packs, unknown issuers, blanks, malformed money, safe evidence, corrupt files and image-only fallback. Widget tests cover selected pages, no automatic save, account changes during extraction and generic errors. Existing rental, trade and fund tests remain part of the full regression run.

An optional private check uses `MANAGED_FUND_SAMPLE_PDF_PATH` and `MANAGED_FUND_SAMPLE_PAGES` (comma-separated one-based ranges). `MANAGED_FUND_EXPECTATIONS_PATH` may point to a private JSON map keyed by range start, containing independently verified component values. Run `flutter test test/integration/managed_fund_sample_pdf_integration_test.dart`. Failed comparisons report only boolean failure and field/page context, never actual or expected financial values. Without the private path the test is explicitly skipped.

Final verification: **232 regression tests passed, two declared skips**; all 19 parser/import-flow tests passed after the final safe-error change. The separately configured private sample/value check passed locally. Strict analysis and the release web build passed. The source PDFs and independent private expectation values were excluded from Git; the temporary expectation file was removed after validation.
