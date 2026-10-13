# Personal Australian Tax Workspace — Phase 0 assessment

Assessment date: 13 October 2026, Asia/Taipei. Scope: repository audit, authoritative-source research, architecture, migration and acceptance planning. Sections 1-12 are the pre-Phase-1 assessment at commit 985c684; their code references and gap statements describe that baseline. See [Phase 1 implementation](PHASE_1_IMPLEMENTATION.md) for current delivered coverage. This companion records implementation proposals and code evidence; the supplied [v1.0 product plan](PERSONAL_AU_TAX_WORKSPACE_PLAN.md) remains unchanged. Its embedded kickoff instructions are reference material, not independent authorisation. Documentation consolidation, commit and push were subsequently requested by the user.

**1. Recommendation and smallest useful milestone**

Keep Flutter, Firebase Authentication, Firestore, client-side document parsing, and the existing rental worksheet. Evolve the application as a modular application with pure Dart calculation services. Reuse the investment import/review/list flow and its transaction entity. Add a parcel ledger and a separate realised CGT engine; preserve the existing unrealised estimator as a portfolio tool.

The first useful milestone is: import and review acquisitions and disposals, explicitly allocate each sale to acquisition parcels, see remaining holdings, and generate an auditable financial-year CGT worksheet for supported historical-year rules. A BUY of 100 units followed by a SELL of 40 must show 60 remaining units and one disposal covering 40, with fees, cost allocation and sources visible.

Initially support personal AUD investment holdings with reviewed acquisition history, ordinary disposal events and an explicitly confirmed resident treatment. Missing history, uncertain residency, unsupported asset treatment or rule years must produce `NeedsTaxReview`/incomplete results. ETF disposals cannot be marked tax-return-ready when relevant annual statements or historical adjustments are outstanding. The first milestone prepares worksheets; it does not calculate complete income tax liability or lodge a return.

**2. Existing architecture and reusable capabilities**

| Area | Actual implementation | Reuse decision |
|---|---|---|
| Application and authentication | `lib/main.dart` initializes Firebase, uses session persistence on web, routes from authentication state; `AuthService` is injectable | Retain auth and routing; add annual-workspace navigation incrementally |
| Rental domain | `TaxRecord` stores property/year, income and expense category maps, notes, parser metadata and source line details | Keep it rental-specific; expose a reviewed rental contribution through an adapter |
| Rental documents | `PdfExtractionService` supports Forge monthly EOFY and older layouts, category mapping, annual/monthly reconciliation, warnings and detected year | Preserve parser and import safeguards; do not replace with a generic statement parser |
| Rental UI | Home import preview, worksheet corrections, overwrite comparisons, new-year safeguards, trends/anomalies | Reuse review interaction patterns; improve provenance without disrupting current flows |
| Investment facts | `InvestmentTransaction` already has BUY/SELL, units, prices, consideration, brokerage/GST, trade/settlement dates and broker/source metadata | Extend backward compatibly rather than creating a second competing transaction model |
| CommSec import | Client PDF extraction produces reviewable drafts with confidence, missing fields and warnings; review/edit/save/list flow exists | Retain; repair direction and sale-amount semantics before real disposal calculations |
| Current CGT tool | BUY valuations at a manual cut-off price/date, holding-period indicator, CSV results | Preserve as an unrealised estimator, driven by remaining parcels once ledger is available |
| Persistence | Injectable `FirestoreService`; records under `users/{uid}`; ownership and field allowlists in rules | Retain per-user paths; add versioned domain repositories and explicit rules |
| Export | Rental CSV/PDF and investment CSV/JSON | Reuse formatting/download boundaries; introduce a versioned backup with restore validation |
| Verification | Model/service/widget tests, fake Firestore, synthetic parser fixtures, optional local PDF checks, separate Patrol smoke target | Preserve existing suite; add deterministic tax and security-rule coverage |

Documentation reviewed includes README, architecture deep dives, production hardening checklist and the investment, parsing, Firebase, testing and release harnesses. README and architecture docs lag the investment feature inventory; future PRs should update the documentation index and clarify estimate versus return preparation terminology.

**3. Correctness and integrity risks in current code**

| Priority | Finding and code evidence | Consequence |
|---|---|---|
| First milestone blocker | Setup filters BUY only at `lib/screens/investment_cgt_calculation_setup_screen.dart:55`; calculator repeats that at `lib/services/investment_cgt_calculator.dart:29` | SELL is stored but ignored, and is not reported among excluded calculations |
| First milestone blocker | Calculator values original units and original total cost at lines 42–43 | Fully or partially sold holdings remain in estimates; no remaining balance or parcel cost exists |
| First milestone blocker | Summary sums discounted positive rows at calculator line 87 and lists losses separately at line 96 | No annual loss allocation or carry-forward. Hypothetical eligible gain $1,000 plus loss $300 yields $500 taxable estimate today, rather than a $350 net gain under the supported ordinary historical resident rules |
| First milestone blocker | `lib/utils/investment_cgt_utils.dart:73` tests `holdingDays > 365`; line 84 halves each positive gain | An indicator, not sufficient discount eligibility; lacks calendar boundaries, residency and event/rule eligibility |
| First milestone blocker | Parser line 258 recognizes literal SELL only, while security-name extraction at line 238 accepts WE HAVE SOLD | A SOLD-only confirmation can be classified BUY without a direction warning |
| First milestone blocker | Parser fallback at line 148 and review at line 134 add consideration and brokerage regardless direction | Suitable BUY fallback cannot define SELL proceeds. Distinguish gross proceeds, disposal fees and net cash settlement |
| High | Transaction deserialization defaults absent total cost to zero at `investment_transaction.dart:83` | Incomplete legacy facts can silently overstate gains; migration must quarantine them |
| High | Money and units are doubles; date construction normalizes invalid dates; invalid money parsing falls back to zero | Introduce exact decimal parsing and strict dates for the new domain; retain original evidence |
| High | `findInvestmentDuplicate` and saving are separate; new transactions use random IDs at `firestore_service.dart:294` | Duplicate detection is useful but not an idempotency guarantee under retries/concurrency |
| High | Draft queue identity omits units/confirmation/account at `investment_draft_sync_service.dart:20` | Distinct drafts can replace one another; failed imports need a stable operation identity |
| High | Rental saves query then write at `firestore_service.dart:110–142`; updates merge without revision conflict checks | Concurrent duplicates and lost edits are possible |
| High | Owner writes/deletes are allowed independent of existing lock state in `firestore.rules` | Current flags are workflow conveniences, not financial-year finalisation controls |
| High | Worksheet switch at lines 305–314 sets local lock, while ordinary save rejects locked state at lines 69–77 | Lock activation cannot persist through ordinary Save; explicit lock/unlock semantics are needed |
| High | Source metadata is filename/parser/version and category/amount details | No source hash, per-field review trail, rule version or immutable calculation snapshot |
| Medium | Rental manual edits change category totals while retaining original line details | Preserve originals but represent corrections explicitly, including reasons and reviewers |
| Medium | Draft queues are session-memory singletons; errors are swallowed for retry | Reload loses drafts; account lifecycle and permanent errors need explicit handling |
| Medium | Rules only shallowly validate rental maps and lists | Typed data and emulator rejection tests are needed; malformed direct-client writes are not covered by fake Firestore |
| Medium | CI runs strict checks but separate deployment relaxes analysis and does not await tests | Release should depend on successful quality checks; pin the supported SDK |

Passing tests do not establish realised-CGT correctness: the calculator has two basic BUY estimate tests. Inspected investment tests lack SELL/SOLD direction, partial sales, allocations, annual losses, leap boundaries, AMIT, DRP and residency coverage. Live Firebase console controls and deployed rules were not audited.

**4. Proposed bounded contexts and models**

Keep existing folders and services initially. Add small typed modules; avoid a package split, state-management replacement, generic accounting framework or new dependency in the first milestone.

| Context | Models and responsibilities |
|---|---|
| Shared tax primitives | `TaxYear` with validated start year and July–June boundaries; date-only values; `Money`, `Quantity`, exact prices; `TaxDocumentReference`; schema and review enums |
| Rental | Existing `TaxRecord`, reviewed rental facts and a summary adapter; category totals remain separate from tax deductibility decisions |
| Investments | Extend `InvestmentTransaction`; add `InvestmentAsset`, `InvestmentParcel`, `ParcelAllocation`, `DistributionReinvestment`, `InvestmentCorporateAction` |
| Annual fund statements | `ManagedFundAnnualStatement`, typed income/offset/withholding/gain components, statement version and fund regime; `AmitCostBaseAdjustment` |
| Capital gains | `CapitalGainEvent`, disposal breakdown, loss applications, `CapitalLossCarryForward`, `TaxCalculationSnapshot` |
| Residency | `TaxResidencyPeriod`, `TaxResidencyEvent`, evidenced market valuation and election records; reviewed asset tax classification |
| Annual return | `AnnualTaxSummary`, section statuses, prefill reconciliation entries and finalisation revisions |

Asset identity includes a stable asset ID, exchange/currency and identifiers where available. Ticker alone is insufficient across name changes or different markets. Broker/account identity helps detect imports; same-security acquisitions remain distinct parcels. Unknown transaction direction must remain a draft, not default to BUY.

Residency should use separate dimensions: Australian/foreign residency and temporary-resident tax treatment. Visa status is evidence, not the tax determination. Periods must be date-specific, non-overlapping and sufficiently complete for each asset's ownership history, not just the selected year. I1 elections belong to the relevant transition and scope; they must not be implemented as arbitrary per-parcel toggles.

Each parcel records acquisition fact revision, acquisition date, original quantity, cost base and reduced cost base. Remaining units and bases are calculated projections. Disposal allocations record parcel ID, exact units, allocated fees/costs, selection method, reviewer and revision. Offer specific-parcel selection first; FIFO may be an explicit saved choice, never a silent legal requirement.

**5. Exact arithmetic and calculation boundaries**

Use Dart `BigInt` coefficient/scale values with strict decimal-string input. Money totals commonly have two decimals; retain greater precision for per-unit prices, quantities and intermediate allocations. Persist canonical decimal strings so web/Firestore serialization does not silently lose integer precision. Currency is explicit. Do not introduce a decimal dependency without an explicit request.

Specify one rounding policy per rule/output boundary. Allocate cents and quantity remainders deterministically with a recorded residual policy; the last partial disposal must consume precisely the remaining allocated cost. Unknown amounts must be represented as missing, never zero. Reduced cost base is distinct from cost base; do not force an artificial gain or loss when proceeds fall between them. Test arithmetic conservation and cross-platform serialization.

Pure Dart services receive reviewed facts and an explicit ruleset. They must not access Firebase, UI widgets, PDF text or AI output. Proposed pipeline:

`Reviewed facts → parcel replay → disposal/adjustment events → annual gain and loss allocation → summary + snapshot`

The unrealised estimator receives remaining parcels and evidence-linked market prices. Its results never enter the annual taxable gain total. AI can suggest a draft or explain an existing breakdown; calculations consume only validated reviewed facts.

For supported historical individual-resident rules, aggregate eligible events by financial year, apply current-year losses and then prior-year losses before discounts, recording each allocation. A configurable documented non-discount-first policy can be offered within lawful choices. Prior loss balances have originating year and usage history; amending a prior year invalidates subsequent dependent summaries. Missing opening balances are not silently assumed zero. Managed-fund gains enter once from the active reviewed statement, with component semantics and gross-up where required; prefill is comparison evidence, not a second income source. [ATO discount and loss guidance](https://smallbusiness.taxsuperandyou.gov.au/capital-gains-tax/the-discount-method), [ATO managed-fund capital gains guidance](https://www.ato.gov.au/law/view/document?DocID=SAV%2FPIG%2F00008&PiT=99991231235958).

Return typed results: `Calculated`, `NeedsTaxReview` and `InvalidInput`, including blocking reasons and source references. An incomplete worksheet may display confirmed components, but cannot claim a complete net capital gain.

**6. AMIT, fund statements and special events**

Record AMIT/non-AMIT/unknown fund regime per statement year, rather than assuming all ETFs are AMITs. Preserve source labels alongside stable component IDs: Australian and foreign income, franked/unfranked components, franking credits, foreign tax offsets, discounted/non-discounted attributed gains, withholding, other non-assessable components, distributions and DRP references. Distinguish attributed income, cash paid and reinvestment; they are not interchangeable totals.

AMIT shortfall increases both bases; excess reduces them, with E10 assessed when excess exceeds cost base. Adjustments normally occur just before year-end, but the legislation places them immediately before a relevant earlier CGT event. Therefore statement receipt date cannot control event replay. [ITAA 1997 sections 104-107A–E](https://www.legislation.gov.au/C2004A05138/2026-07-01/2026-07-01/text/original/epub/OEBPS/document_3/document_3.html).

The annual statement's aggregate adjustment needs a reviewed allocation to relevant interests/parcels. Prefer issuer-provided per-unit/period evidence; do not invent a universal year-end-holdings allocation. Where attribution for sold units or allocation timing cannot be substantiated, block finalisation for review. Preserve later-arriving corrected statements and recompute affected disposal years. DRP is a separate acquisition and must not duplicate an adjustment.

I1 requires an evidenced residency transition, asset classification, valuation, exception review and any election. The same legislation, sections 104-160 and 104-165, contains the event and individual choice. Keep unsupported transitions provisional; confirm temporary-resident exceptions and discount restrictions against the applicable-year law and ATO guidance before enabling definitive results. A transition does not automatically mean all securities receive the same treatment.

**7. Tax-rule versioning and independent confirmation**

Do not encode one timeless `0.5` discount or a `365` holding threshold. Proposed initial rule coverage is FY2024–25 and FY2025–26, subject to design confirmation and independent verification, using acquisition/event dates and calendar holding rules. Additional historical years require reviewed packs. Discount eligibility excludes acquisition and event days; test anniversary, next-day, leap-day and timezone-normalized date inputs. [ATO holding-period guidance](https://smallbusiness.taxsuperandyou.gov.au/capital-gains-tax/the-discount-method).

Research found enacted changes: the Treasury Laws Amendment (Tax Reform No. 1) Act 2026 was assented to on 26 June 2026. Its application provisions introduce changed CGT treatment and ordering for 2027–28 onward; Treasury describes inflation-based arrangements and minimum CGT tax from 1 July 2027, alongside rental changes. Keep those years unsupported until separately reviewed. This is a concrete reason for event-date/year rule selection and future valuation/election fields, not a reason to implement a full tax-liability calculator now. [Enacted reform and application provisions](https://www.legislation.gov.au/C2026A00049/asmade/2026-06-26/text/original/epub/OEBPS/document_1/document_1.html), [Treasury overview](https://treasury.gov.au/policy-topics/taxation/budget2026-27).

Maintain a rule register containing rule ID/version, effective event dates, applicable years, authoritative URLs, retrieval/review dates, reviewed interpretation and approved fixtures. Some ATO full pages returned access errors; indexed ATO guidance was available, and federal legislation was retrieved. This assessment confirms architectural implications, not a complete independently certified ruleset.

Independent confirmation before enabling calculation coverage:

- Calendar/leap-day eligibility, event-specific acquisition rules and relevant discount exclusions.
- Acquisition/disposal brokerage handling, GST included amounts and separate reduced-cost treatment.
- AMIT parcel attribution, effective timing for pre-year-end sales, E10 eligibility and non-AMIT payment rules.
- Statement gross-up/component mapping and reconciliation of issuer fields to ATO labels for each year.
- I1 taxable-Australian-property classifications, temporary-resident exceptions, scope/consequences of elections and residency-related discount restrictions.
- Pre-CGT/indexed assets, rollovers, foreign currency, foreign securities and corporate actions; unsupported cases need review.
- FY2026–27 guidance and the enacted FY2027–28 transition, minimum-tax, loss ordering, valuation and rental provisions.

**8. Persistence, review and source lifecycle**

Retain existing collections. Proposed new records all live under `users/{uid}`:

| Collection | Role |
|---|---|
| `tax_documents` | Minimal document identity/hash/type/parser reference; default no uploaded PDF storage |
| `import_runs` | Source identification, draft status, warnings, parser version and idempotency outcome |
| `investment_assets` | Stable security identities and reviewed classifications |
| `investment_fact_revisions` | Immutable reviewed transaction/adjustment facts; legacy transaction link |
| `parcel_allocations` | Immutable sale selections and superseding corrections |
| `managed_fund_statements` plus revisions | One active statement revision per fund/account/year, retaining superseded evidence |
| `residency_periods` / `residency_events` | Reviewed timeline, valuations, elections and supporting references |
| `capital_loss_balances` | Versioned opening/used/closing balances by origin year and loss class |
| `annual_returns/{taxYear}` | Workspace status, input generation and current snapshot pointer |
| annual-return `snapshots` / `reconciliations` | Immutable derived results and manual prefill matches/discrepancies |

Raw extracted candidates, reviewed facts and derived outputs are separate records. Raw text stays transient by default; persisting a sensitive excerpt requires explicit product retention decisions. A document reference contains SHA-256, document kind, source location/page when available and a safe display name. Overrides create fact revisions with prior value, new value, reason, reviewer and timestamp; they do not erase extracted evidence.

Use a broker/account-scoped confirmation identity plus normalized semantic fingerprint, and an exact source-byte hash. Hash identifies identical bytes; a different scan can still be the same transaction. Hash collisions/conflicting normalized facts require review. Reserve import identity and create fact revision atomically; retries return the same result. Hash computation needs a vetted implementation; assess existing dependency support before requesting any added dependency.

Use optimistic revision checks for edits and a per-user calculation-input generation updated atomically with fact changes. Reject publication of a snapshot calculated from an older generation. Derived parcel balances are caches, not independently editable truth. Snapshot data includes year, all input IDs/revisions or a chunked immutable manifest, source references, input hash, allocation policies, rule version, engine version, arithmetic policy, results/breakdown, timestamp and completeness state. Use bounded documents rather than one unbounded history array.

Rules enforce owner isolation, allowed fields, schema versions, bounded value representation, immutable revisions, preserved creation timestamps and authorised lifecycle transitions. Finalisation checks reconciliation of current inputs; finalized snapshots deny update/delete. Corrections produce an amendment revision and preserve the old snapshot. Enforce affected-year locking on historical fact/allocation changes, with emulator tests for direct-client bypass. Client-side arithmetic remains reproducible/auditable, but owner-authored results are not third-party certified calculations.

PDF retention remains local by default. If cloud storage is later requested, implement matching user-scoped Storage rules, retention/deletion controls and size/type restrictions first. Mask account identifiers by default in exports; never log raw documents or put private samples in Git. A versioned JSON backup includes facts, revisions, sources, allocations, rule IDs, snapshots and reconciliation records, with validation/dry-run restore and duplicate protection. Existing CSVs alone are not a restoreable backup.

**9. Backward-compatible migration strategy**

1. Export existing records before opt-in migration; deploy rules compatible with legacy and new records before enabling writes.
2. Keep `tax_records` unchanged and adapt read-only into the annual workspace. Missing review evidence becomes a review requirement, not an assumed reconciled state.
3. Treat absent investment schema version as legacy. Preserve original doubles and strings in legacy records; convert through a deterministic adapter with precision checks, recording the conversion and any uncertainty.
4. Reconcile security identity, direction, historical SELLs, missing costs and opening holdings. A legacy BUY does not prove an unsold parcel. Flag incomplete history and ambiguous sale amounts.
5. Create stable migrated fact revision identities linked to legacy ID. Rerunning migration must produce no extra acquisitions or statements. Create prospective projections only after reviewed history.
6. During rollout define one authoritative fact writer. Existing UI edits must create a new revision/invalidate dependent snapshots through the same service; avoid independent dual writes.
7. Provide per-user progress and conflict reporting; rollback switches readers to untouched legacy records. New final snapshots remain preserved. Do not delete legacy data in initial phases.

**10. Phased PR roadmap and proposed files**

| Phase / PR | Small reviewable deliverable | Dependencies |
|---|---|---|
| 0 | This assessment and design review | No implementation |
| 1A | Characterization fixtures; strict dates/decimals/TaxYear; BUY/SELL/SOLD draft direction and amount validation; reviewed rule register | Confirm first supported years and scope |
| 1B | Parcel replay and explicit sale allocations; oversell/incomplete-history guards; revised import identity and fact revision persistence | 1A and compatible rules |
| 1C | Realised disposal engine, annual losses/carry-forward, reproducible snapshots and breakdown export | Reviewed rule pack, 1B |
| 1D | Disposal allocation/review UI and FY worksheet; unrealised estimator on remaining parcels; legacy migration dry-run | 1B–1C and emulator verification |
| 2A | Structured manual annual statement entry/review/versioning before adding format-specific parsers | Fact/review foundation |
| 2B | AMIT timeline and parcel allocation, DRP acquisitions, statement corrections and cost history | Independently reviewed attribution/timing |
| 2C | Fund/direct-gain deduplication and source/prefill reconciliation | 2A–2B |
| 3A | Residency timeline, evidence-backed valuations, I1 review/election handling | Independently confirmed special rules |
| 3B | Unified FY dashboard, rental adapter, manual dividends/interest/other-income/deductions/offset records | Reviewed mappings and residency state |
| 3C | Annual reconciliation/finalisation/amendments and versioned backup/worksheet export | Complete dependent modules and rules tests |

Proposed files: add primitives and domain types under `lib/models/tax/` and `lib/models/investment/`; pure `investment_parcel_ledger.dart`, `realised_cgt_calculator.dart`, `annual_cgt_calculator.dart` and statement adjustment services under `lib/services/`; extend existing investment transaction/parser/review/setup files; add small allocation/year-summary screens; extend Firestore repositories and `firestore.rules`; add mirrored service/model tests and emulator rule tests. Preserve existing `TaxRecord`, rental extractor, worksheet and routes through adapters. Add tax-rule and migration documentation under `docs/`, revise `docs/harness/investment-cgt.md` to distinguish estimate rules from realised rules, and make release CI depend on quality checks. Use `codex/` implementation branches and Lore-format commits when implementation is authorised.

Annual UI will show separate income/deduction/gain/loss/credit categories by financial year, never one sum mixing offsets with income. Every section shows Not started, Documents missing, Imported, Needs review, Reconciled, Ready for review, Ready for tax return or Finalised. Status transitions follow evidence and completeness; explicitly reviewed not-applicable sections are distinct from missing data. Expandable calculation steps link to reviewed fact and document revisions. Source changes make reconciliation stale. The five requested UX questions map to FY sections, parcel cost history, disposal breakdown, missing/reconciliation issues and the reviewed annual worksheet export.

**11. Acceptance and regression specification**

First implementation phase is accepted when:

- BUY 100 / SELL 40 leaves exactly 60; selling the rest leaves zero units and zero residual allocated basis. Oversells and sales before acquisitions are blocked.
- Multiple same-security parcels retain distinct dates/bases; a sale spanning parcels uses explicit saved selections. Choice changes create a revision and recomputation.
- Gross proceeds, acquisition fees and disposal fees reconcile; GST is not added twice. Missing costs, invalid dates and ambiguous direction cannot create definitive results.
- Supported historical ordinary eligible gain $1,000 with $300 current losses gives $350 net gain; $1,000 eligible plus $400 noneligible gains with $500 losses gives $450 using the recorded noneligible-first policy.
- Current-year and prior losses are consumed in documented order; unused loss balances persist by originating year and cannot offset ordinary income.
- Anniversary/next-day/leap-year boundary fixtures match reviewed legal interpretation; missing or changing residency produces review requirements.
- Exact duplicate import, retry and concurrent import create one fact. Distinct acquisitions are not accidentally merged. Migration replay is idempotent.
- Each output contains complete inputs/revisions, sources, allocation steps, rules, arithmetic policy and timestamp. Source edits invalidate dependent snapshots and prior-year amendments invalidate later loss balances.
- Existing rental parsing/review/save safeguards, CommSec BUY import, auth, exports and estimate UI remain operational. Estimates use remaining holdings and are separate from tax totals.
- Owner/cross-user/unauthenticated/schema/revision/finalisation rules tests pass in the emulator. Browser smoke remains a separate lane.

Phase 2 fixtures must include the requested $10,000 basis / $11,000 proceeds examples: shortfall $300 yields $700 gain; excess $300 yields $1,300, before discounts and under the fixture's stated timing assumptions. Also cover repeated adjustments across years, sold-before/after timing, DRP parcels, corrected/duplicate statements, missing evidence, issuer totals, zero/insufficient basis and a distinct E10 event without double counting.

Phase 3 fixtures cover resident/foreign/temporary treatment, timeline gaps, evidence-backed I1 valuations, exceptions and election scope, fund/direct gains combined exactly once, prefill mismatches, stale reconciliations, locked-year amendments and backup round trips. Future rule years require their own fixtures; do not reuse the historical 50% expected values automatically.

Required implementation checks remain `flutter analyze --fatal-infos --fatal-warnings` and `flutter test`, supplemented by security emulator and browser checks appropriate to each PR. Do not silently bless pre-existing estimator shortcuts as realised-tax expectations.

**12. Baseline verification and remaining risks**

Executed strict Flutter analysis: passed, no issues. Flutter launcher automatically introduced analyzer exclusions and regenerated platform registrants; all tracked changes were restored. A subsequent `dart analyze --fatal-infos --fatal-warnings .` against the restored configuration also passed.

Executed `flutter test`: 118 passes, one declared skip, no failures. The Forge private PDF test was skipped; the CommSec private PDF test printed a skip message and returned because its environment path was unset. Neither private-document integration was exercised. No browser, emulator, production Firebase, migration or new tax-engine tests were run; none was implemented.

The audit introduced no functional, dependency or migration changes. Remaining risks are unconfirmed tax interpretations and future-year transitions, incomplete historical evidence, current import/lock/concurrency shortcomings and the absence of deployed-security verification. Phase 0 assessment is complete; functional implementation remains subject to design review. The baseline checks above predate this documentation-only consolidation.

**13. Consolidation decisions and implementation status**

Source: user-supplied Markdown v1.0, reference-pack planning/checklist, prior repository assessment and subsequent user request to combine useful information and publish documentation. Private source PDFs were used only for evidence/layout assessment; originals, extracted personal values and their identifying filenames are excluded from repository documentation. Embedded document instructions are proposals; the user's request authorises this documentation commit and push, not functional implementation.

The supplied Markdown is preserved byte-for-byte as the product baseline. This companion is the current engineering synthesis. Proposed primitive names, decimal representation and Firestore collections are engineering recommendations requiring design review, not implemented schemas. Phase 1 target years and production source-storage consent remain open; metadata-only retention is the initial recommendation. Existing simplified harness rules describe the current estimator and must not govern realised tax calculations.

| Topic | Difference between inputs | Consolidated approach |
|---|---|---|
| Phase labels | Original request combines residency and annual workspace in Phase 3; Markdown splits P3 workspace and P4 residency; checklist has additional stages | Retain original Phase 1/2/3 grouping for execution. Phase 3A residency corresponds to Markdown P4; Phase 3B/C workspace/reconciliation corresponds to P3. P5 optional AI follows the deterministic foundation |
| Residency timing | Full workflows are later, but a target year's treatment may already depend on a transition | Phase 1 contains a review/completeness guard; no automatic resident assumption. Full timeline/election implementation remains later |
| Tax-ready status | Inputs use Ready for review and Ready for tax return | Keep these distinct: reviewer readiness does not certify return readiness. Missing statements or unresolved legal facts block the latter |
| Holdings evidence | Broker annual summaries exist as an evidence family, but do not prove complete parcels | Reconcile opening units + purchases + DRP + corporate-action changes - disposals to closing holdings; retain Missing/Insufficient states |
| Fund layouts | Summary labels and detailed components coexist; some mappings specify resident individuals | Record issuer/year/layout, validate columns and totals, and do not add summary values to their details or infer residency from labels |
| Source hashes | A combined master PDF is available, not necessarily all standalone original bytes | Hash the actual supplied bytes and reference constituent page ranges; do not claim hashes of unavailable originals |
| Extraction | Some layouts show encoding/reading-order problems | Keep format-specific parsers and structured manual fallback; text extraction success alone does not validate amounts |
| Future-year rules | Baseline links include historical ATO guidance | Use the source register and effective dates; unsupported years remain NeedsTaxReview rather than inheriting a timeless discount |

| Milestone | Status as of 2026-10-13 | Evidence / next gate |
|---|---|---|
| Phase 0 repository audit and design proposal | Done | Sections 1-12; baseline strict analysis and 118 test passes |
| Phase 0 documentation consolidation | Done | Supplied baseline plus this synthesis, requirements and source register; documentation links/privacy checks |
| Functional design review | Done for Phase 1 scope | User authorised Phase 1; scoped historical AUD worksheet and review gates are recorded in the implementation note; broader legal/production review remains outstanding |
| Phase 1A-D investment foundation | Done (scoped implementation) | See implementation note for exact delivered scope, four-parcel boundary and verification; review/release pending |
| Phase 2A-C fund/AMIT/DRP ledger | Not started | Confirm attribution/timing rules and evidence coverage |
| Phase 3A residency | Not started | Independent classification, valuation and election review |
| Phase 3B-C workspace/reconciliation/export | Not started | Reviewed source contributions and finalisation rules |
| Optional AI convenience | Not started | Deterministic foundation first; no paid service approved |

Update this table with actual PR links and verification evidence as implementation proceeds. A documentation publication does not change implementation status.

Change log: 2026-10-13 - retained supplied v1.0 baseline; consolidated repository findings and useful pack requirements; recorded phase differences and unresolved decisions; excluded private evidence and local paths.

Implementation update: 2026-10-13 - Phase 1 implemented on an isolated branch following user authorisation; original assessment retained as historical evidence. No private PDFs or taxpayer fixtures added.
