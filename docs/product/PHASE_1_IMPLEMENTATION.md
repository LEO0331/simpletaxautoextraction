# Phase 1 investment foundation

Implemented 13 October 2026 on an isolated implementation branch. The supplied v1.0 product plan remains unchanged. This note records the delivered scope; full individual tax liability, lodgment, fund statements and residency-event treatment remain outside Phase 1.

## Use the feature

1. Open Investment CGT and upload a supported CommSec confirmation, or choose manual transaction entry. Parsing is local. Enter an account identifier and a source reference for manual records; review date, direction, quantities, gross consideration and fees against evidence.
2. Review old records deliberately before calculating. BUY/SOLD/SELL direction is explicit; legacy/unreviewed records require a fresh direction choice. A BUY total must equal consideration plus brokerage; a SELL net cash amount must equal gross consideration minus brokerage. GST already included in brokerage is not added again.
3. Open Realised CGT and parcel ledger. Select the financial year, then assign each sale to specific earlier acquisition parcels, in chronological order. No FIFO is assumed. At most four parcels per sale are supported in this release; larger allocations need further implementation/review.
4. Review recorded remaining units and acquisition bases. These are brokerage-only acquisition projections, before fund/corporate adjustments. The disposal breakdown separately shows gross proceeds, fees, acquisition basis and the tax cost/reduced cost bases including disposal fees.
5. Confirm complete history/holdings reconciliation, continuous Australian residency/non-temporary treatment, supported personal AUD capital holdings and absence of relevant fund/corporate/special changes. Enter reviewed opening losses, their originating start years (`2023=100.00`, one per line) and evidence. A verified zero balance also needs review and evidence.
6. Calculate the annual worksheet, inspect loss applications and provenance, then save an immutable snapshot or export JSON. Any source/selection change marks current worksheets stale and requires reload/recalculation. The latest 20 saved snapshots remain visible; changed-generation snapshots are historical evidence, not current figures.

## Calculation boundaries

- Pure calculation services depend on a read-only fact interface, dates and exact decimal values; they do not import Firebase, widgets or PDF parsers. The existing transaction model implements that interface and keeps legacy APIs for compatibility.
- Decimal coefficients use `BigInt`; exact strings persist quantities and money. Inputs support up to 12 fractional quantity digits and cents for monetary facts. Allocation uses documented cent rounding with residual conservation; the final disposal consumes the remaining parcel basis. Discounted half-cent values remain exact in worksheets.
- Only FY2024-2025 and FY2025-2026 ordinary positive AUD acquisition/disposal worksheets are enabled. Current-year losses precede verified prior balances, with oldest-origin balances consumed first and a recorded non-discount-first gain policy. Net capital losses cannot offset ordinary income.
- Ordinary holding periods use calendar anniversaries excluding acquisition/event days. The specific leap-day anniversary boundary remains `NeedsTaxReview` pending independent interpretation; it is not converted to a silent 365-day rule.
- Missing/unreviewed facts, oversells, stale or duplicate selections, mixed users, repeated source facts, same-day acquisition order, pre/indexed-era acquisitions, unverified loss origins, unsupported years or unresolved residency/fund/special treatment withhold a definitive net gain.
- The separate unrealised estimator values remaining parcels when sales exist. Unresolved sales withhold complete estimates. Legacy no-sale performance estimates remain available; missing/invalid bases are excluded. Their hypothetical discounts are not annual tax results.

The result is a reviewed worksheet under explicit assumptions, not a certified tax return or professional legal classification. Fund-attributed gains and AMIT/DRP/corporate-action adjustments must be handled in later phases; the first implementation cannot claim completeness where they affect these records.

## Persistence and migration

Existing rental collections and workflows are unchanged. Investment facts retain `users/{uid}/investment_transactions`, with schema v2 exact strings and date-only ISO fields plus UTC-midnight timestamps. Broker/account-scoped SHA-256 source reservations make repeated imports idempotent; differing facts under the same identity require an explicit revisioned correction. Distinct confirmations remain separate acquisitions even when amounts coincide.

Edits check the expected revision, preserve creation time and append immutable history. The first explicit legacy update archives the raw pre-update record as revision zero before creating revision one; there is no automatic bulk migration. Legacy timestamps alone do not establish a reviewed civil trade date: verify against the source when upgrading.

Voiding removes a mistaken transaction from active calculations without erasing history. Unlock before changing financial facts or voiding a locked record. A voided record can be restored through explicit review. Allocation revisions cite all transaction revisions. Every fact/selection mutation advances a ledger generation; snapshot publication checks that generation and input revisions again. Verified zero-activity years can retain explicit history/loss provenance without fake transactions.

New owner-scoped collections are `investment_sources`, `investment_metadata`, `investment_allocations` (with revisions) and `investment_calculation_snapshots`. Snapshots contain exact results, inputs/source references, revisions, rules/engine versions, allocation/rounding policies, evidence, hashes and timestamps. Queued investment drafts remain session-only, with an explicit retry restricted to the current user; durable offline storage and backup restore are later work.

## Security and release gates

| Surface | Control / evidence |
|---|---|
| Cross-user access | Authenticated owner-only paths; actual emulator read/write rejection tests |
| Invalid/schema/unknown fields | Type/field validation; malformed values rejected or review-gated |
| Concurrent edits/imports | Atomic reservations, expected revisions and ledger generation checks |
| History erasure | Immutable revision/snapshot rules; audit-preserving voids |
| Stale selections/results | Referenced revisions checked; current worksheet/export invalidation |
| Legacy mutation | Revision-zero raw archive required atomically on upgrade |
| Confidential PDFs | Local parsing/hashing; no document bytes stored; all PDFs ignored by Git; synthetic public tests only |
| Account session changes | New ledger view clears previous account inputs/results on sign-out and binds actions to its owner |
| Wrong legal treatment | Explicit supported-year/context gates; unsupported or uncertain scenarios remain NeedsTaxReview |

Deploy the revised `firestore.rules` before releasing the updated client. No production Firebase settings or rules were changed during implementation. Client-authored snapshots are audit records, not independent third-party attestations. Broader production security/console review and full browser journeys remain separate release work.

Completed verification: strict Flutter analysis and analysis with restored original configuration; 175 Flutter test passes and one declared skip; `scripts/test_firestore_rules.py` against a local demo emulator, release web build with the existing Pages base path, and JavaScript execution of exact-decimal/SHA-256 vectors. Private PDF integrations remain optional and were not exercised. The rules emulator's four-parcel boundary is tested explicitly; the five-parcel attempt is rejected. CI runs the same pinned, checksum-verified emulator separately from Flutter tests.

Change log: 2026-10-13 - delivered Phase 1 scoped ledger, review, annual worksheet and persistence/security foundation; retained future phases and unresolved legal/format boundaries.
