# Tax Workspace Harness

Source: Phase 3 combines existing source modules into reviewable yearly workpapers.
Trigger: Read when changing tax-workspace models, coordination, UI, backups or finalisation.
Expiry: Revise when verified tax-law coverage or storage boundaries expand.

- Reuse `TaxDecimal`, the existing rental/fund facts and annual CGT worksheets. Never add fund gain components again to income or CGT totals.
- Income, deductions, capital gains, credits and withholding are separate categories; no complete tax-liability or lodgment claim.
- Missing sources and explicit reviewed non-applicability are distinct. A status toggle cannot remove unresolved source issues.
- Residency is evidenced, effective-dated and manually classified. I1 scenarios are excluded from annual totals/bases; unknown/special treatment remains review-gated.
- Source generations and fingerprints must be verified before finalisation/export, and after asynchronous snapshot loading. Project finalisation's own generation advance to avoid false immediate staleness.
- Prior-year CGT corrections must invalidate later opening-loss assumptions, including when the investment generation has not changed. Normalize balances by origin and compare closing/opening amounts.
- Freeze finalised records; reopen via a reasoned amendment. Imported archives are always unreviewed evidence.
- Workspace backups preserve source/revision audit data without overwriting live external domains. Validate schema/owner/limits before any write; interrupted restores remain unreviewed and resumable.
- Keep the paired Firestore parent/history validators intact. Verify fully populated nested-field boundaries with the genuine emulator before changing caps.
- Deploy the updated client and rules together: rental writes now require an atomic workspace-generation change.
- Private originals, source values and runtime files do not belong in Git or public fixtures. Use synthetic tests.
