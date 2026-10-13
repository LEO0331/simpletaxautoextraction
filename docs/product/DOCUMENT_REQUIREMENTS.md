# Document requirements and evidence coverage

Version 1.0 - 13 October 2026. Source: user-provided product plan and reference checklist, reconciled with the Phase 0 code audit. This is a generic evidence specification; private inventories and taxpayer facts remain outside the repository.

| Phase | Evidence families | Required checks |
|---|---|---|
| 0 design | Repository, supplied plan, relevant-year authoritative guidance, acceptance criteria | Separate current code from proposals; record source access and unresolved interpretation |
| 1 investment | BUY/SELL contract notes, broker CSV/activity reports, opening and closing holdings, transfers, brokerage and corporate actions | Verify acquisition history and explicit sale allocation; summaries alone may be insufficient |
| 2 fund/DRP | Annual statements for each held fund/year, issuer guides, corrected statements, distribution/reinvestment advice, unit ledger | Validate fund regime/layout, component totals, adjustment timing, DRP cost/units and residual cash |
| 3 residency | Reviewed residency timeline, supporting classification, dated market valuations, asset classification and election evidence | Visa/travel details do not determine tax residency; unresolved treatment stays NeedsTaxReview |
| 3 annual workspace | Rental statements, interest/expense invoices, depreciation/capital works schedules, employment, bank interest, dividends, foreign income, deductions/offset evidence | Category-specific review; rental worksheet totals are not automatically confirmed deductions |
| 3 reconciliation/export | Manually supplied ATO prefill, prior returns/notices, verified opening losses and completed workpapers | Match source contributions once; explain differences; block finalisation for unresolved gaps |
| Every phase | Synthetic layouts and independently reviewed expected results | No private originals or derived personal fixtures in Git, PRs, logs or public CI |

## Coverage and provenance

Track account/asset/year/document family with Available, Reviewed, Missing or Insufficient evidence status, source ID, actual-byte hash, parser/layout version, page/field reference, review revision and outstanding issue. Availability is not completeness. Do not put the real coverage register in this public documentation.

Reconcile opening units + acquisitions + DRP + corporate-action unit changes - disposals to closing units. Cross-reference issuer and broker records so a DRP acquisition is recorded once. Historical years may be needed for cost bases even when only one return year is being prepared.

Use source-specific parsing with field/column association and total checks. Preserve summary versus component semantics, attribution versus cash, resident-only mappings and statement revisions. Unknown layout, corrupt text or conflicting totals must lead to review/manual entry, not guessed numerical facts.

A merged pack is one source file: its hash proves only those supplied bytes. Use constituent page ranges for provenance until standalone originals are available. Do not infer original-file hashes or certified duplicate identities from a merged inventory.

## Privacy and retention

Default proposal: source metadata and reviewed structured facts, with original PDFs kept locally. Cloud PDF retention requires a separately reviewed storage/access/deletion policy. Keep raw extraction transient and disable personal text/amount logging. Do not copy personal dates, amounts, names, addresses, TFNs, account/reference numbers, barcodes or PDF metadata into public fixtures. Generate fresh synthetic examples preserving only necessary layout characteristics.

Do not scrape myGov or assume an authorised ATO integration. Prefill is user-supplied reconciliation evidence. Missing evidence cannot be generated from public sources.

Change log: 2026-10-13 - initial sanitised requirements and coverage specification.
