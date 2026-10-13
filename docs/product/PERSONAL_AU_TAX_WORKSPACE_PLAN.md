# Personal Australian Tax Workspace — Product & Engineering Plan

**Project:** `LEO0331/simpletaxautoextraction`  
**Document status:** Proposed specification; **not implemented**  
**Version:** 1.0  
**Prepared:** 13 October 2026  
**Target repository location:** `docs/product/PERSONAL_AU_TAX_WORKSPACE_PLAN.md`

> **Purpose.** Evolve the existing Flutter/Firebase rental-tax and investment-tracking app into a persistent, auditable, multi-year Australian personal tax workspace. The app should prepare and reconcile information for myTax and accountant review; it should **not** claim to lodge returns or provide definitive tax advice.

## 1. Decision summary

**Product statement:** “Keep the evidence once, calculate consistently, review exceptions, and assemble annual Australian tax-return inputs.”

- **Do not rewrite the application.** Preserve the existing Flutter, Firebase Auth, Firestore, Forge statement parser, property worksheets, CommSec import, and working tests.
- **Do not create a second investment tracker.** Extend the existing CGT domain and clearly distinguish portfolio valuation from realised taxable events.
- **First engineering milestone:** parcel-aware BUY/SELL reconciliation, followed by a historical AMIT/AMMA cost-base ledger.
- **Long-term differentiator:** connect rental property, investments, tax-year summaries, supporting documents and reconciliation statuses in one personal workflow.
- **Do not use an LLM to decide tax figures.** Use deterministic, versioned calculation services; optional AI is limited to extraction assistance and explanations with manual review.
- **Avoid “1M context” workflows.** Persist structured transactions, tax events, source references and calculation snapshots; retrieve only relevant records for each user action or coding task.

## 2. What the repository already supports

| Existing capability | Evidence in current repository | Decision |
|---|---|---|
| Rental-property worksheet and annual tracking | `lib/models/tax_record.dart`, `lib/services/pdf_extraction_service.dart`, property screens | Preserve and eventually aggregate into annual workspace. |
| Forge monthly/EOFY statement extraction and import review | `README.md`, parser tests | Preserve; do not regress. |
| Firebase login, user-isolated Firestore collections, security rules | `lib/services/firestore_service.dart`, `firestore.rules` | Extend rules and tests for new domains. |
| CommSec trade confirmation PDF parsing | `lib/services/parsers/commsec_trade_confirmation_parser.dart` | Reuse for acquisition/disposal source records; enhance validation. |
| Investment transaction storage / duplicate checks | `lib/models/investment_transaction.dart`, Firestore service | Extend without destructively changing existing data. |
| Investment cut-off value and potential CGT discount estimate | `lib/services/investment_cgt_calculator.dart` | Keep as **unrealised valuation / scenario estimator** only. |
| CGT domain instructions and tests | `docs/harness/investment-cgt.md`, `test/services/investment_cgt_calculator_test.dart` | Update instructions when semantics change. |

**Confirmed gap:** the current CGT calculation loops over BUY records, marks potential discount eligibility by holding days and values them using a user-selected market price. It does not consume SELL records to allocate actual disposals to acquisition parcels or incorporate AMIT adjustments, capital-loss ordering or a complete annual net capital gain. Do not label its output a tax-return-ready CGT result.

**Additional audit point:** the existing `totalCost` field may be ambiguous for SELL transactions. Define separate gross proceeds, disposal costs and net proceeds before implementing realised CGT logic. Review the existing 365-day discount heuristic; eligibility is jurisdiction- and residency-dependent.

## 3. What makes the proposed app different

| Tool / workflow | Primary purpose | Your app's proposed role |
|---|---|---|
| ATO myTax | Official return preparation and submission | Independent evidence tracking, reconciliation and return-input preparation, **not** lodgment. |
| Investment portfolio trackers | Performance and investment-specific reporting | Cross-domain personal tax records tied to original tax statements and rental records. |
| Spreadsheets | Flexible ad hoc calculations | Repeatable, typed, tested calculations and permanent year-over-year provenance. |
| Long AI chats | Explanation, exploratory analysis | Small targeted queries against structured records; no need to reconstruct history. |
| Existing SimpleTax app | Property extraction and investment valuation | Parcel-level ETF tax history plus annual return workspace. |

**Design criteria:** answer “Where did this number come from?”, “Which financial year does it belong to?”, “What changed after an amended statement?”, and “What still needs review?” without re-uploading every historic PDF.

## 4. Scope boundaries

### In scope, incrementally

1. Individual Australian financial-year records, source-file metadata and reconciliation status.
2. Australian investment BUY/SELL ledger, fractional units, parcels, brokerage and adjusted cost bases.
3. ETF / managed fund annual statement capture, including AMMA tax components and AMIT cost-base net adjustments.
4. DRP acquisitions, distributions, fund-attributed capital gains and loss carry-forwards.
5. Separate realised CGT and unrealised portfolio valuations.
6. Rental-property summary integration, bank interest, dividends and ATO prefill comparisons over later phases.
7. Residency timeline and exceptional tax events requiring manual tax review.
8. Explainable calculations, corrections, snapshots and exportable workpapers.

### Explicitly out of scope for the first releases

- Electronic ATO/myGov access or lodgment without a separately authorised and legally supported integration.
- A definitive, comprehensive tax-liability estimator before tax-rule coverage is demonstrated.
- One-size-fits-all treatment of residency, CGT event I1, international assets or foreign property transactions.
- Production AI parsing of arbitrary documents without reviewed, testable outputs.
- Storing sensitive original tax PDFs in an unrestricted GitHub repository.

## 5. Data and tax-domain design

### Proposed bounded contexts

- **Rental:** existing `TaxRecord`, property categorisation, yearly rental income and deductions.
- **Investment ledger:** assets, accounts, transactions, parcels, DRP and corporate actions.
- **Managed funds:** annual AMMA/other fund statements and sourced tax components.
- **Capital gains:** disposals, parcel allocation, cost-base events, current/prior losses, discount calculations and audit trace.
- **Residency:** effective-dated residency evidence, elections and tax-review flags.
- **Annual tax workspace:** one per financial year, reconciled category totals and tax-return input mappings.

### Proposed core entities (names subject to design review)

| Entity | Key fields / constraints |
|---|---|
| `InvestmentAsset` | Asset ID, market, identifier/ticker, issuer, fund tax regime, currency. |
| `InvestmentTransaction` | Existing model plus explicit BUY/SELL cashflow meaning; immutable import metadata. |
| `InvestmentParcel` | Acquisition date, acquisition event, total/original units, remaining units, initial/adjusted cost base, asset/account linkage. |
| `DistributionReinvestment` | Fund, date, cash entitlement, units acquired, acquisition cost and evidence. |
| `ManagedFundAnnualStatement` | Issuer, tax year, statement revision, taxable component fields, document reference, review status. |
| `CostBaseAdjustmentEvent` | Parcel/allocation reference, tax year, adjustment amount, AMIT excess/shortfall type, explanation and source. |
| `CapitalGainEvent` | Disposal, allocated parcels, proceeds, incidental costs, gain/loss, applicable rule set and calculation trace. |
| `CapitalLossCarryForward` | Origin FY, amount, utilised amount, remaining balance and reconciliation trace. |
| `TaxResidencyPeriod` | Residency category, effective dates, evidence status, reviewer notes. |
| `AnnualTaxSummary` | FY, input category totals, completeness and reconciliation status, calculation snapshot version. |
| `TaxDocumentReference` | Document type, tax year, local/private storage reference, hash, redaction flag, upload and review metadata. |

### Storage and precision requirements

- Keep existing Firestore paths intact. Introduce new user-scoped collections or typed subcollections only after migration review.
- Use immutable original events plus subsequent correction events, or equivalent versioned audit records. Never silently mutate past acquisition facts.
- Use a fixed-precision strategy (for example integer minor units for currency and explicit decimal precision for fractional units/allocations). Define rounding policy and document calculation order.
- Store source field, financial year, rule version, calculation version, timestamp and manual overrides for all material results.
- Implement idempotent import, source fingerprinting, account/source identity separation and safe duplicate resolution.
- Historical re-calculation must be deterministic and allow a frozen snapshot for a completed financial year.

## 6. Tax calculation rules: requirements, not hardcoded assumptions

### 6.1 BUY/SELL parcel accounting

- Preserve individual acquisition lots. For every disposal, record which lots and quantities were assigned and why.
- Support partial sales and conservation of units; a parcel may not have negative remaining quantity.
- Support explicit lot selection and a documented default **only when appropriate**; do not claim FIFO is mandatory Australian tax law.
- Distinguish trading costs from asset acquisition costs, sale proceeds and proceeds net of disposal expenses.
- Keep unrealised market valuation calculations separate from realised disposal results.

### 6.2 AMMA / AMIT

- Record annual fund-attributed income, distribution details, CGT components, withholding/franking offsets and AMIT net cost-base fields, but avoid treating every fund as an AMIT.
- **AMIT cost base net amount — Shortfall (increase)** generally increases cost base; **Excess (decrease)** generally decreases cost base. A decrease beyond cost base may create a capital gain. This should be implemented only with the relevant ATO rules and statement semantics confirmed.
- Allocate annual cost-base changes to the correct units/parcels based on reviewable evidence and a documented allocation policy; accommodate mid-year purchases and sales.
- DRP normally creates new acquisition units; do not conflate it with an adjustment to existing units.
- Prevent double counting between fund-attributed gains, actual asset disposals and prefilled data.

### 6.3 Annual capital gains / losses

- Combine realised gains and losses, fund-attributed capital-gain components and previous loss carry-forwards according to financial-year-specific rules.
- Apply allowable capital losses before the relevant discount; do not apply 50% to each lot in isolation and add it up.
- Separate **potential eligibility** from a **confirmed applied discount**; validate holding period, asset eligibility and residence-dependent restrictions.
- If a rule or relevant fact is unknown, return `NeedsTaxReview` rather than a falsely definitive amount.

### 6.4 Residency and cross-border events

- Use an effective-dated residency timeline. Do not infer tax residency from visa status or travel date alone.
- CGT event I1, available elections, former temporary-resident rules and foreign/temporary resident discounts require authoritative checking and possibly a professional determination.
- Support scenario modelling, manual valuations and accountant-reviewed decisions **later**, not automatic cross-border tax outcomes in Phase 1.

## 7. Required documents and test evidence

### Immediately — required to start Phase 0 (no personal tax data needed)

1. This plan (`PERSONAL_AU_TAX_WORKSPACE_PLAN.md`).
2. Current repository source, README, `docs/harness/*`, security rules and tests (already in the repo; **do not upload duplicates**).
3. Your written scope decision: individual Australian returns, initial target FY(s), priority broker(s)/fund(s), and whether private cloud storage of original PDFs is permitted.

**Codex can complete the architecture/gap analysis and create synthetic fixtures without any real statements, TFNs or tax-return records.**

### Later — for implementation / parser validation, preferably redacted

| Document / data | Why needed | When |
|---|---|---|
| 1 CommSec BUY and 1 SELL confirmation (ideally including partial sale) | Verify parser fields, fees, proceeds and source identity. | Phase 1 |
| Broker transaction CSV or tax-year trade history | Reconcile all lots and disposals; detect missing historic acquisitions. | Phase 1 |
| Start-of-period holdings statement (units and acquisitions, if available) | Verify historical lot completeness and balances. | Phase 1 |
| At least one AMMA statement from each **distinct layout**, for one financial year | Design accurate field mapping including AMIT and fund-attributed CGT. | Phase 2 |
| A prior and a later AMMA statement for the same ETF | Test cumulative cost-base adjustments across years. | Phase 2 |
| DRP election and reinvestment confirmation / distribution advice, if applicable | Verify additional units, dates and unit cost. | Phase 2 |
| Corrected or amended annual statement, if one exists | Test revision handling and re-calculation. | Phase 2 |
| Existing Forge statement from an unsupported layout (only if encountered) | Test rental parser regression. | Phase 3+ |
| Redacted myTax/ATO prefill example or manually transcribed category totals | Reconcile published/prefilled amounts against calculated values. | Phase 3+ |
| Residency timeline **with a tax adviser’s classification if uncertain** | Build and validate optional residency scenarios without inferring legal status. | Phase 3+ |

**Privacy rules for supplied samples:** remove TFN, name, address, date of birth, bank details, broker account number, confirmation identifiers, QR/barcodes and personal document metadata. If amounts and dates are needed for a real regression test, use a private, access-controlled location; otherwise provide synthetic versions preserving the PDF layout. Do not commit unredacted samples, Firebase secrets, API keys or production records.

## 8. Phased implementation roadmap and gates

| Stage | Implementation deliverable | Exit / acceptance gate |
|---|---|---|
| **P0 — Audit & specification** | Current architecture inventory, known CGT gaps, precise models, threat model, tax rule list, migration plan, user stories and estimate. | No code rewrite; engineering review of scope and correctness risks. |
| **P1 — Realised CGT ledger** | BUY/SELL parcel assignment, remaining holdings, realised CGT, separate unrealised estimator, import review improvements. | 100% of synthetic test disposals reconcile units, cashflows and capital gains; no regression to rental/CommSec imports. |
| **P2 — AMMA/AMIT + DRP** | Annual statement data-entry/review, source links, cost-base events, DRP lots, multi-year adjustments. | Test multi-year acquisitions/sales, excess-to-zero case, amended statements and avoidance of double counting. |
| **P3 — Tax-year workspace** | Aggregate reviewed investments and rental summaries; per-category completeness, manual bank/dividend items, ATO prefill comparison and exports. | Every displayed amount traces to records; no unreviewed totals silently marked return-ready. |
| **P4 — Residency extensions** | Effective-dated residency profile, event scenario screens, I1/election workflow, tax review state. | No automatic definitive treatment for unsupported legal scenarios; professional validation for production use. |
| **P5 — Optional AI and convenience** | Assisted extraction for additional document formats and plain-language explanations, with explicit review. | AI cannot mutate confirmed source values or make unvalidated legal/tax decisions. |

### Phase 1 acceptance examples

- BUY 100 units, SELL 30: remaining units = 70; no disposed quantity remains in open holdings.
- Buy at two different prices; SELL fewer than total units: recorded lot allocation matches resulting gain and holdings.
- Sales before acquisition or above available units are blocked with actionable errors.
- Brokerage and GST inclusion are not added twice; PURCHASE cost base and DISPOSAL proceeds are independently represented.
- No unintended changes to historical rental records, imports, existing Firebase paths or unrelated screens.
- A historical snapshot remains reproducible after a reviewed correction.

### Phase 2 acceptance examples (illustrative)

- Original cost base $10,000, AMIT shortfall $300, proceeds $11,000 → gain before applicable discount = $700.
- Original cost base $10,000, AMIT excess $300, proceeds $11,000 → gain before discount = $1,300.
- Separate test: AMIT excess larger than available basis; zero basis + additional capital gain are handled as required by rules.
- DRP creates its own acquisition parcel; total holdings and cost bases reconcile.
- AMMA revisions and reimports retain old and new versions and explain the delta.

These are **synthetic assumptions**, not substitutes for ATO legal rules or review of actual statement fields.

## 9. UX and operating model

Proposed top-level navigation: **Tax Years · Rental Properties · Investments · Documents · Reconciliation · Exports**.

A tax year should show:

- Financial year and residency review status.
- Rental property income/expense net position.
- Dividends, managed-fund income, interest and other entered income.
- Realised CGT, losses, adjusted ETF cost bases and remaining carry-forwards.
- Source coverage: Not started / Missing documents / Imported / Needs review / Reconciled / Ready for review / Finalised.
- Click-through “Explain this amount” showing formulas, linked events, source file and rule version.

Default workflow: **upload/import → detect → review → save evidence → recalculate → reconcile → export/finalise**. Export should include category workpapers and a machine-readable backup; actual ATO return lodgment remains outside the product scope.

## 10. Security and operations

- Preserve the owner-scoped Firestore approach and add automated Firebase emulator security rule tests for new collections.
- Restrict source-document upload/read paths; storing private file contents should be optional and explicit.
- Preserve audit records and rejected/changed imports; no silent overwrites of a finalised tax year.
- Add schema and calculation versioning, backwards-compatible reads and a reversible migration strategy.
- Do not store identity/financial secrets in Git, screen captures or analytics/logging systems.
- Require `flutter analyze --fatal-infos --fatal-warnings`, `flutter test`, parser regression tests and security rule tests on relevant PRs.
- Avoid introducing paid AI services or additional backend infrastructure without a documented reason and cost/security review.

## 11. Instructions for Codex: how to record and maintain this plan

**Proposed canonical path:** `docs/product/PERSONAL_AU_TAX_WORKSPACE_PLAN.md`.

1. Create a new branch, e.g. `docs/personal-au-tax-workspace-plan`.
2. Add this Markdown file **unchanged** as the baseline product specification; do not overwrite other documentation or create a new application.
3. Read `README.md`, architecture docs, `docs/harness/investment-cgt.md` and current source code. Produce a gap analysis document separately, e.g. `docs/product/IMPLEMENTATION_GAP_ANALYSIS.md`.
4. If actual code differs from a claim in this plan, note the discrepancy in the gap analysis and propose a change. Do not silently rewrite the business requirements.
5. Add an `Implementation status` table in the gap analysis listing each milestone as `Not started`, `In progress`, `Blocked` or `Done`; reference PRs and test output.
6. Update this plan only for **approved** scope/tax-rule decisions. Maintain version and a dated change log so subsequent Codex sessions do not lose context.
7. First response should be a concise analysis and proposed Phase 1 PR breakdown. Do not implement all phases in a single PR.

### Copy/paste Codex kickoff instruction

```text
I want you to retain the attached PERSONAL_AU_TAX_WORKSPACE_PLAN.md as the canonical project roadmap in this repository.

1. Create a documentation branch (do not change main directly).
2. Save the supplied plan as docs/product/PERSONAL_AU_TAX_WORKSPACE_PLAN.md.
3. Audit the actual codebase and existing docs, especially the investment CGT calculator, CommSec parser, rental worksheet, Firestore schema and tests.
4. Write docs/product/IMPLEMENTATION_GAP_ANALYSIS.md with a factual existing-versus-proposed feature matrix, technical and tax-rule risks, migration approach, and Phase 1 acceptance criteria.
5. Treat source code as evidence of CURRENT behaviour and the plan as PROPOSED requirements; flag disagreements.
6. Keep a dated change log and implementation status so later Codex sessions can resume without relying on chat history.
7. Do not make functional code changes yet. Return the documentation diff and the recommended sequence of small PRs for my review.
```

## 12. Open decisions before Phase 1

- **Tax years:** Which year is the first target, and how far back should historical ETF acquisitions be reconstructed?
- **Statement formats:** Which ETF issuers/brokers are in the initial scope? (Start with actual supported files, not every possible issuer.)
- **Lot selection:** Allow explicit parcel selection from the outset; specify whether to offer an editable default strategy.
- **Document storage:** Metadata only, local encrypted storage, or private Firebase Storage with explicit consent?
- **Tax residency:** Is residency-event modelling essential for the initial target FY, or an expert-reviewed later phase?
- **Export:** CSV/JSON audit pack first, or include accountant-friendly PDF summary in P3?
- **Operating model:** Personal single-user tool first, with code designed for separate Firebase-authenticated users; no public multi-user tax product assumptions.

## 13. Authoritative reference starting points

These are research references, not a claim that a complete tax-law implementation has been verified for a particular taxpayer/year. Confirm the applicable financial-year guidance before coding rules.

1. ATO — AMIT/AMMA statement components: https://www.ato.gov.au/businesses-and-organisations/trusts/in-detail/managed-investment-trusts/managed-investment-trusts-overview/attribution-managed-investment-trusts/attribution-method-for-managed-investment-trusts/attributing-amounts-to-members
2. ATO — AMIT cost-base net amount, excess and shortfall: https://www.ato.gov.au/forms-and-instructions/capital-gains-tax-guide-2021/whats-new/trust-distributions/non-assessable-payments-from-a-trust
3. ATO — Share and unit-trust acquisition/disposal records: https://www.ato.gov.au/forms-and-instructions/capital-gains-tax-guide-2022/part-a-about-capital-gains-tax/keeping-records
4. The repository’s `docs/harness/investment-cgt.md` is an **existing code policy**, not a source of Australian tax law; review and revise its simplified discount semantics before claiming realised CGT accuracy.

---

### Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-10-13 | Initial product scope, repository assessment, phased roadmap, required document checklist and Codex recording instructions. |
