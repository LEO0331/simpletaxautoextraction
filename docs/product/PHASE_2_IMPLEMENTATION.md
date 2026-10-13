# Phase 2 — Reviewed fund statements, AMIT and DRP

Implemented on 13 October 2026 from merged Phase 1 (`b168c0d`). This note records delivered scope; the supplied v1.0 plan remains the historical baseline.

## Using the feature

1. Open **Investments → Annual fund statements, AMIT and DRP**. Record the issuer, layout/version, fund, account, financial year and private source reference. Enter all statement components, explicitly reviewing zero values.
2. Reconcile gross attributed capital gains with twice the discounted component plus the other component. These are separate fields, not additional amounts to add together. Income, credits, withholding and cash distributions remain separately recorded for the future tax-year workspace.
3. Allocate the signed AMIT amount to evidenced interests: positive shortfall increases both bases; negative excess reduces them. Each slice identifies the acquisition parcel, units, date and attribution evidence. Retained interests use 30 June; sold interests use the relevant sale date and sale ID. An adjustment to sold units affects only that allocated slice, not the retained units.
4. Enter each DRP acquisition once through the existing reviewed BUY workflow using its actual acquisition date, units and reinvested cost. Link that BUY to its distribution entitlement, reinvestment and residual cash. The link creates no second parcel. Resolve an existing broker import before adding another acquisition.
5. Deliberately mark the reconciled statement reviewed. Open the parcel ledger to inspect adjusted holdings, cost-base history, E10 gains and combined annual CGT. Review complete history, missing statements, residency, supported assets and originating loss balances before relying on a worksheet.
6. Edit the existing statement for an amendment. Its active facts are replaced, immutable revisions retained, and the ledger generation advanced. Recalculate current figures; earlier saved worksheets remain historical. Void/restore also retain history.

## Calculation and provenance

The deterministic `parcel-v2` ledger applies historical adjustments chronologically before subsequent transactions, or immediately before an evidenced disposal. Both bases floor at zero; an excess beyond the relevant basis creates a separate E10 event. The full adjustment is not also counted as income or a capital gain. Annual `annual-cgt-v2` combines direct disposals, grossed attributed gains and E10 once, then applies reviewed current and prior losses before an eligible historical individual discount. Acquisition-boundary and residency exclusions remain review-gated.

Every worksheet includes statement and transaction revisions, source references, explicit allocation evidence, basis changes, fund gain events and loss applications. Statement saves and allocation trials replay the relevant reviewed facts. Snapshot saves check the current generation and statement revisions as well as transaction/allocation revisions. The unrealised estimator also replays fund statements, including zero adjusted bases, instead of valuing original acquisition costs.

The owner-scoped `users/{uid}/managed_fund_statements/{id}` identity is account/fund/year; issuer or layout spelling changes cannot create an additional active annual statement. Its `revisions/{revision}` records are immutable. Firestore rules protect ownership, schema, money/date shapes, unknown fields, revision history and ledger generation. Client-authored numerical results remain workpapers, not server-certified tax results.

## Scope and remaining boundaries

- Manual structured review is delivered. Issuer-specific AMMA PDF parsers remain future work pending redacted layout fixtures. No original PDF, extracted PDF text or personal source fixture is uploaded or committed.
- Automatic tax calculations remain limited to the reviewed FY2024–2025 and FY2025–2026 resident-individual rules used in Phase 1. Earlier source years can inform cost history; future tax-rule years remain unsupported.
- Non-AMIT statements can be captured as drafts, but their distinct non-assessable payment/E4 treatment requires tax review. Indexed components, corporate actions, foreign currency, residency transitions and unusual trust concessions remain outside automatic coverage.
- Statement components are a supported subset. Do not fold unsupported indexed gains or special concessions into another component merely to make totals reconcile.
- Explicit attribution evidence is required. The app does not infer a valid parcel allocation by dividing an annual total across year-end holdings.
- Each statement currently supports four adjustment slices and four DRP links. Larger annual records require expanded, emulator-tested storage support; do not split one annual statement into duplicate active records.
- Production Firestore rules deployment and taxpayer-specific source verification remain release steps. This change does not deploy rules, publish the site, create a PR or merge the branch.

## Tax references checked for this design

The [ITAA 1997 July 2026 compilation, ss 104-107A/B](https://www.legislation.gov.au/C2004A05138/2026-07-01/2026-07-01/text/original/epub/OEBPS/document_3/document_3.html) provides AMIT adjustment timing and excess-to-zero/E10 mechanics. Relevant provisions were retrieved; historical-law applicability and each issuer's attribution still require review.

Indexed [ATO managed-fund guidance](https://www.ato.gov.au/law/view/document?DocID=SAV%2FPIG%2F00008&PiT=99991231235958) and [LCR 2015/11](https://www.ato.gov.au/law/view/print?DocID=COG%2FLCG201511%2FNAT%2FATO%2F00001) support grossing up discounted attributed components before personal losses/discount. Full-page retrieval was unavailable in this session. [TD 2000/3](https://www.ato.gov.au/law/view/view.htm?docid=TXD%2FTD20003%2FNAT%2FATO%2F00001) distinguishes DRP acquisitions from bonus shares and identifies reinvested dividends as acquisition cost; this is a starting reference, not universal approval for every fund's reinvestment arrangement.

## Verification

Synthetic tests cover the requested $10,000 basis/$11,000 proceeds examples ($700 shortfall-adjusted gain and $1,300 excess-adjusted gain), multiple years, partial sales, before-sale/year-end timing, insufficient basis/E10, DRP, duplicate and amended statements, missing references, combined losses, portfolio integration, revisions and account isolation. Final full-suite, strict analysis, web build and real Firestore emulator results are recorded after integration below.

- Full Flutter regression suite: **213 passed, one declared skip**. Optional private PDF layout fixtures were not supplied to the test run; synthetic fixtures were used.
- `flutter analyze --fatal-infos --fatal-warnings`: passed. Direct Dart analysis also passed after restoring launcher-generated configuration/platform files.
- Flutter release web build with `/simpletaxautoextraction/` base path: passed; no deployment.
- Genuine local Firestore emulator: passed ownership, schema, locks, immutable history/snapshots, generation, malformed fields and four-parcel allocation boundaries. Managed-fund checks include full four-adjustment/four-DRP creation and update, fifth-entry rejection, missing-history rejection, corrections and voids.
- Read-only review issues fixed: draft review gates no longer prevent structurally valid non-AMIT capture, and reviewed acquisition/sale IDs are visible and copyable in the editor and ledger.
- No new dependencies or rental/parser rewrites. Existing acquisition, exact-decimal, ledger and loss-ordering services are reused rather than introducing a second tracker.
