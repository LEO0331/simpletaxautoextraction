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

## Calculation Rules

For BUY transactions:
- `costBase = totalCost`
- If `totalCost` is missing, calculate `consideration + brokerage`.
- Do not add GST again if brokerage/costs already include GST.
- Holding period uses trade date by default.
- `holdingDays > 365` means potentially eligible for the 50% CGT discount indicator.
- Losses have taxable gain after discount of `0` and should be marked as estimated capital losses.

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
