# Phase 3 — Tax-year workpapers and residency review

Implemented 14 October 2026 from merged main `042a383`, including the Phase 2 PDF parser. This release implements the agreed 3A–C review workflows, not a complete income-tax liability or lodgment engine.

## Workflow

Open the calendar icon **Tax-year workspace** from the dashboard. Initial supported worksheet years are FY2024–2025 and FY2025–2026.

1. Record effective-dated residency periods with an exclusive end date, classification and evidence. Confirm each period after checking its source. The timeline must cover the financial year and, when an investment CGT worksheet is selected, its acquisition history. Gaps, overlaps, unknown classifications and foreign/temporary treatment remain review-gated. Visa status is never converted into tax residency.
2. Record salary, bank interest, dividends, other income, deductions and other offsets with source references and exact AUD amounts. Enter assessable dividend income including the applicable gross-up; record its franking credit separately. Never repeat the same deduction/offset in both the main amount and an ancillary field. Corrections and voids retain immutable revisions.
3. Review each rental source and its ownership share. Use 100% if the underlying worksheet already contains the taxpayer's share. The adapter applies the evidenced percentage once to yearly income and deductions, rounding the resulting money to cents. It rejects unknown categories, changed sources, nonfinite numbers and genuine fractional-cent legacy values. Tax deductibility still requires deliberate review.
4. Review fund income and offsets through the Phase 2 statements. Select a current reviewed annual CGT worksheet. Fund-attributed capital gains and E10 are included through that worksheet exactly once, not added again to ordinary fund income. Direct disposals and known carried losses cannot be hidden by marking capital gains not applicable.
5. Mark every section reconciled, or explicitly not applicable with evidence. Imported/missing/unreviewed sources cannot become complete merely by changing a status. Enter available ATO prefill totals for comparison; differences are review issues, not silent overrides. Exact CGT half-cent precision is retained, so rounding differences require review.
6. Finalise only a complete supported workpaper. Finalisation freezes the report, source facts, review inputs and dependency fingerprints. It does not certify a tax return or lodge it. An explicit amendment reason reopens the year; prior finalised reports remain readable.
7. Export workpaper JSON or a versioned workspace backup. Restore into a new workspace for the same authenticated owner. Review flags reset, and original sources/revisions remain immutable imported evidence. Existing workspaces are preserved.

## Residency and I1 boundaries

The I1 form records event date, asset reference, evidenced market value, cost/reduced cost bases, classification, election review and adviser reference. It shows undiscounted valuation-difference scenarios and preserves the decisions for review. These scenarios never mutate parcels, reset bases, or enter annual CGT automatically. A deferral review concerns all eligible assets at the event; inconsistent recognise/defer choices are flagged.

All I1 scenarios and uncertain/non-resident/temporary-resident treatment currently block finalisation. Evidence capture is delivered; professional legal classification, exception/election effects, foreign-resident discount apportionment and automatic tax outcomes remain outside verified calculation coverage. An asserted classification alone does not establish that an asset falls within a statutory exception.

The [ITAA 1997 July 2026 compilation, ss 104-160 and 104-165](https://www.legislation.gov.au/C2004A05138/2026-07-01/2026-07-01/text/original/epub/OEBPS/document_3/document_3.html) was retrieved for the event, market-value comparison and individual election scope. The exceptions concern specified property/interests, and the election covers all assets within the event. This reference supports the review design, not a taxpayer-specific conclusion. [ATO changing-residency guidance](https://www.ato.gov.au/forms-and-instructions/capital-gains-tax-guide-2021/whats-new/does-capital-gains-tax-apply-to-you/foreign-residents-temporary-residents-and-changing-residency) was available through indexed historical guidance; it is not sufficient to approve every current-year special case.

## Source integrity and carry-forwards

Manual sources use deterministic category/source identities and optimistic revisions. Rental reviews bind to the exact rental source fingerprint. Workspace/item/rental changes advance a shared workspace generation; investment facts retain their existing ledger generation. Both generations are checked when loading, exporting and finalising, including after snapshot reads. Source changes invalidate loaded calculations rather than producing a mixture of old and new records.

The coordinator compares originating-year opening losses with the most recent earlier in-app CGT worksheet's structured closing balances. A changed balance, stale predecessor, amendment in progress, or unreviewed intervening year blocks continuation. Positive known carried losses require an annual CGT worksheet even in an otherwise disposal-free year. External prior-loss evidence remains supported by the existing reviewed CGT workflow when no earlier in-app anchor exists. Generation checks are deliberately conservative: historical CGT workpapers may need recalculation after later investment imports.

A finalisation write advances generation itself. Its frozen fingerprint represents the committed generation, so a freshly finalised report matches its current sources. Subsequent changes make it historical; an amendment never rewrites that report.

## Storage and release

New data stays under `users/{uid}/tax_years/{startYear}`: configuration revisions, versioned manual items, and immutable finalised/imported snapshots. `tax_workspace_metadata/current` tracks generation. Parent/history writes must match atomically. The rules split residency/evidence checks from I1/prefill checks across those mandatory writes to remain within Firestore's expression limit while preserving typed validation.

Existing rental records retain their schema. Their writes/deletes now advance workspace generation atomically; records in finalised years require an amendment first. Existing investment, fund and rental parsers remain intact. There is no destructive data migration or new dependency.

**Deploy the Phase 3 Firestore rules with the updated client.** The user's previously deployed Phase 2 rules do not include these collections and write requirements. Old clients cannot continue single-document rental writes after the new rules enforce generation. This implementation does not deploy production rules or publish the client, and does not create or merge a PR.

## Backup semantics and limits

The backup contains year configuration, current manual entries, all year/manual revision history, immutable workpapers, and the referenced rental/fund/investment source audit. Restore retains the original source facts/history as immutable imported evidence and restores current workspace/manual entries as an unreviewed draft. It does not overwrite live rental/investment/fund collections, transfer owners, or certify imported snapshots. Existing live references must be checked before reconciliation; this is a workpaper backup, not an automatic whole-account migration.

All payloads are validated before writing. Restore is resumable: a network interruption leaves an incomplete unreviewed draft; retrying the same backup is idempotent. Edited or unrelated existing workspaces are rejected. Original files remain local; PDF bytes/raw text are not part of this backup.

Current bounds: four residency periods and four I1 review records per year; ownership percentages up to 12 fractional places; money to cents except preserved CGT calculation precision. Backups support 200 current manual items, 100 archives and 5 MB total; source audit is bounded to 800 KB and each immutable archive to 900 KB. Oversized workpapers are rejected explicitly. Wider issuer/residency/tax-rule coverage and larger archival storage require further verified implementation.

## Verification

Synthetic tests cover section completeness, source deduplication, rental ownership/corrections, exact category totals, prefill differences, residency gaps/overlaps, I1 election review, omitted/stale CGT, losses after earlier corrections, finalisation generations, amendments, backup round trips/history, owner rejection and account changes during loading/editing. Genuine emulator checks cover ownership, unknown/malformed fields, source generations, locked-year edits, immutable histories/imports and fully populated four-period/four-I1 boundaries. Final full-suite, strict-analysis and release-build results are recorded after integration.

- Full Flutter regression suite: **275 passed, two declared skips**. No private PDF fixture paths were configured.
- Strict Flutter analysis: passed. Direct Dart analysis against restored repository configuration also passed.
- Release web build with `/simpletaxautoextraction/`: passed; no production deployment.
- Genuine Firestore emulator: passed Phase 1/2 regression rules plus new workspace isolation, schema, revision, finalisation/amendment, imported-history, rental-generation and precision-boundary checks.
- Read-only review findings fixed: backup source evidence/history retention, post-snapshot load races, unsupported-year finalisation, and ownership precision parity. Added predecessor-loss validation to prevent carrying stale balances through a corrected prior-year CGT selection.
- No new dependencies, original-PDF uploads or unrelated parser rewrites. Existing calculation and source services are reused.
