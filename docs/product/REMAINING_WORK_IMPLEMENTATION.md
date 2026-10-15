# Remaining plan work — implementation record

Updated 15 October 2026, Asia/Taipei. The supplied [v1.0 product plan](PERSONAL_AU_TAX_WORKSPACE_PLAN.md) is preserved unchanged. This record maps the user's subsequent request to finish the remaining deterministic work to its implementation and limits. Optional AI is explicitly excluded by the user. Scoped features are implemented and local release verification passed. The repository owner controls PR review, merge and production rules deployment.

## Phase mapping

| Plan / follow-up | Implementation | Current gate |
|---|---|---|
| P0 specification | Architecture/gap assessment, document requirements, source register and preserved baseline | Original assessment retained as history |
| P1 realised ledger | Reviewed BUY/SELL facts, explicit parcel allocations, exact remaining units and separate unrealised estimates | Implemented, including larger detail sets and evidenced split/consolidation replay |
| P2 funds and DRP | Reviewed annual statements, AMIT adjustments/E10, attributed gains, linked existing DRP acquisitions, corrected-statement revisions | Implemented, including bounded non-AMIT E4 and larger adjustment/DRP sets |
| P3 annual workspace | Financial-year categories, rental contributions, exact manual items, prefill reconciliation, immutable finalisation/amendment history | Implemented, including accountant exports, inventory and source-scoped adviser decisions |
| P4 residency | Effective-dated timeline, evidenced I1 reviews and all-covered-assets election review, explicit adviser workpapers | Review workflow; unsupported legal treatment does not become an automatic calculation |
| Release verification | Same-commit CI dependency for Pages, strict analysis, unit/widget suite, genuine rules emulator and real headless browser | Done locally: analysis, 339 tests, both rules suites, real Chrome integration, release build and public asset check passed |
| Document coverage | Per-year/account/security evidence inventory, page/hash references, canonical/CommSec CSV review, DRP advice and exact holdings reconciliation | See [coverage/import details](DOCUMENT_COVERAGE_AND_IMPORTS.md); required missing evidence blocks completion |
| Capacity | Linked typed detail sets for allocations, fund adjustments/DRP, residency/I1 and adviser decisions; chunked immutable archives | Implemented; genuine emulator passed twelve-item and greater-than-1-MB archive cases |
| Accountant exports | CSV and paginated PDF annual workpapers with exact amounts, issues, source fingerprint and provenance | Outputs are reviewed workpapers, not a lodged return or tax-liability assessment |
| Full-account recovery | Owner-scoped structured backup, validated references/history, immutable recovery archive and resumable draft activation | Restored financial facts require fresh review; archived approval history is passive evidence |
| P5 optional AI | Excluded | No implementation planned or required by the current user scope |

## Automatic calculation and human decisions

`TaxRuleRegistry.supportedYearStarts` contains 2020 through 2025: FY2020–21 through FY2025–26. This registers the bounded ordinary Australian resident individual worksheet rules, not every asset, taxpayer, event or tax in those years. Dates, evidence completeness, loss origins and reviewed fact revisions still control eligibility. A custom-year workspace supports an evidenced expert workpaper; FY2026–27 and later do not inherit historical discounts or loss ordering automatically.

Non-AMIT statement review distinguishes tax-deferred, tax-free and tax-exempt amounts. Reviewed allocations can change cost base and reduced cost base differently; a supported surplus creates an E4 event without duplicating fund income. The statement's labels and allocation evidence are required. AMIT E10 remains a distinct event.

Split/consolidation decisions identify an existing acquisition parcel, effective date, old/new units and evidence. Replay conserves total bases and acquisition history. This workflow does not infer demerger, merger, takeover, rollover or other corporate-action tax treatment.

Foreign-currency entry requires dated, evidenced AUD-per-unit conversion and separately reviewed forex/election implications. It prepares a reviewed AUD transaction draft; a conversion rate alone does not determine all foreign income, forex or residency consequences.

Complex residency, indexation, unsupported corporate events and future-year law can be recorded through an explicit complete annual adviser decision. The decision supplies all annual category totals, closing loss balances, rule/evidence references and the precise legal review issues it covers. Its source fingerprint binds the decision to the current financial inputs. It replaces the annual totals once and records its provenance. It does not teach the application new law, waive missing documents or unreviewed numeric facts, resolve stale source snapshots, or certify a return. Source changes require a fresh decision. I1 event decisions are separately evidenced and do not silently remove holdings or turn an election into arbitrary parcel choices.

Complete income-tax liability, Medicare levy, all offsets and eligibility determinations, automatic unsupported special-case treatment, and ATO lodgment remain outside this product's implemented scope. Manual section entry records the user's reviewed values rather than determining deductibility or legal entitlement.

## Storage, recovery and privacy

Schema-2 headers refer to typed, immutable detail records through a count and canonical content hash. Readers reconstruct the logical record only after validating the complete set. Missing, changed or mismatched details fail closed. Legacy inline records remain readable. Small write batches control Firestore validation budgets; they are not a four-item limit on the user's records. Ordinary Firestore document limits, client memory and documented import/backup file limits still apply.

Workspace finalisation archives are chunked structured data, allowing larger source audits without storing an oversized single document. Backup recovery validates the complete owner-scoped file and references before activating data. It accepts an empty target account or an unchanged retry of an interrupted restore; it does not overwrite unrelated active data. Current facts return as drafts. Old allocations, approvals, finalisations and snapshots remain readable recovery evidence and require independent review before reuse.

Original PDFs remain local and excluded from Git. Source references use hashes of the supplied bytes and selected page ranges; a combined file does not imply unavailable standalone originals were hashed. No confidential PDF pages, extracted personal values, taxpayer identifiers or production records belong in repository fixtures, screenshots or logs. Public fixtures and emulator/browser accounts use invented examples. Structured account backups contain private financial data and must be handled privately by their owner.

## Release evidence

Verified on 15 October 2026:

- Strict `dart analyze --fatal-infos --fatal-warnings .`: passed with no issues.
- Full Flutter suite: 339 passing tests, two declared private-PDF skips, successful suite completion. Confidential sample PDFs were not exercised by those skipped tests.
- Genuine Firestore emulator: legacy rules suite and capacity suite passed. The latter covers twelve residency periods, twelve fund adjustments, twelve parcels, a structured archive larger than 1 MB, hostile typed rows, immutable publication, stale generations, owner isolation, inventory, corporate-event history and recovery evidence.
- Final web release build: passed in 48.3 seconds, including the Wasm dry run. Read-only public landing-page and asset checks passed.
- Git tracked-file privacy check: no PDFs tracked. The baseline plan has no diff.
- Real headless Chrome integration: passed login, reviewed section/item persistence, stale-source reload, year switching, authentication clearing, re-login, required-missing inventory and logout. The framework-error collection was empty.

Both emulator rules suites were rerun sequentially after browser verification and passed. Local emulators and ChromeDriver were stopped after testing.

Local emulator checks verify checked-in rules; the public landing-page check verifies serving and assets. Neither proves that production Firebase contains the reviewed rules. The user creates and merges the PR and controls production rules deployment.

Primary legal references and applicability limits are maintained in the [source register](ATO_SOURCE_REGISTER.md). Historical Phase 1–3 test counts and earlier four-item limits remain in their original implementation notes as records of those releases; this document describes their subsequent extension.
