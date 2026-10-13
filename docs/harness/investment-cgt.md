# Investment CGT Harness

Source: Investment CGT Tracker was added as a separate domain from property tax worksheets.
Trigger: Read when editing investment transaction models, screens, parser integration, calculation logic, exports, or Firestore methods.
Expiry: Revise when the CGT tracker becomes a standalone package or when saved calculation sessions become first-class persisted records.

## Domain Boundary

Investment data must stay separate from property tax records.

Use:
- `lib/models/investment_transaction.dart`
- `lib/models/investment_cgt_calculation.dart`
- `lib/models/investment_cgt_summary.dart`
- `lib/services/investment_cgt_calculator.dart`
- `users/{userId}/investment_transactions/{transactionId}`

Do not overload `TaxRecord` for share/ETF transactions.

## Required Wording

Always show or preserve this disclaimer in user-facing CGT flows:

```text
This is an estimate only and does not constitute tax advice. Please confirm with a qualified accountant or tax adviser.
```

Use `Potential CGT discount eligible`, not `CGT discount applied`.

## Legacy unrealised estimate and realised worksheet boundaries

For BUY transactions:
- `costBase = totalCost`
- If `totalCost` is missing, calculate `consideration + brokerage`.
- Do not add GST again if brokerage/costs already include GST.
- Holding period uses trade date by default.
- Calendar holding eligibility excludes acquisition and disposal days; the old `holdingDays > 365` helper is not a realised-tax rule.
- Losses have taxable gain after discount of `0` and should be marked as estimated capital losses.

When sales exist, replay reviewed explicit allocations through the cut-off date and value remaining parcels only. An unresolved sale withholds a complete holdings estimate rather than retaining disposed units. Hypothetical discounted estimates are not annual net capital gains.

Phase 1 adds `InvestmentParcelLedger`, `AnnualCgtCalculator`, exact `TaxDecimal` values and the realised ledger screen. It supports specific parcel selection (up to four parcels per sale for server-side rules validation), reviewed positive AUD ordinary acquisitions/disposals and historical FY2024-2025/FY2025-2026 resident-individual worksheets. Same-day order evidence, indexed-era acquisitions, special asset/currency treatment, fund changes and residency transitions require review. Leap-day anniversary boundary interpretation remains review-gated.

Apply current-year losses then prior balances in originating-year order before any eligible discount; record non-discount-first gain selection. Preserve exact half-cent discount results in worksheets, rather than rounding each gain independently. Opening balances must reconcile by year with evidence, including an explicitly reviewed zero balance.

Legacy records are unreviewed until deliberately checked. Reviewed facts include exact decimals, UTC-normalised date-only fields, source references and revisions. Imports reserve a broker/account-scoped source identity atomically; conflicting source facts require explicit correction. Voiding removes a record from active calculations but retains immutable history. Source/allocation changes advance the ledger generation and invalidate current worksheets; historical snapshots remain readable.

No PDFs are persisted by this feature. Hash source bytes locally, keep private originals outside Git and use synthetic tests. The rules must be deployed before releasing the updated client; this implementation does not deploy production rules.

## User Flow

Preferred flow:

```text
Upload broker PDF -> parse on client -> review/edit extracted draft -> duplicate check -> save to Firestore -> calculate with manual cut-off prices -> show result summary
```

Duplicate detection priority:
- Confirmation number if present.
- Fallback: ticker, trade date, units, total cost, transaction type.

## Verification

For CGT changes, run:

```bash
flutter test test/services/commsec_trade_confirmation_parser_test.dart
flutter test test/services/investment_cgt_calculator_test.dart
flutter test test/screens/investment_cgt_module_test.dart
flutter analyze --fatal-infos --fatal-warnings
```

If touching Firestore methods, also run:

```bash
flutter test test/services/firestore_service_extended_test.dart
```
