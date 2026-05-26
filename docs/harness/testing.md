# Testing Harness

Source: CI on GitHub Actions uses a different Flutter version and environment from local development, and long widget journeys have been flaky.
Trigger: Read when adding tests, fixing CI, changing widgets with complex layout, or editing GitHub Actions.
Expiry: Revise when the CI Flutter version and browser/e2e strategy are pinned and stable.

## Test Strategy

Keep `flutter test` deterministic:
- Prefer service/model tests for business logic.
- Keep widget tests short and screen-scoped.
- Avoid giant multi-screen journeys in `flutter test`.
- Put full browser workflows in Patrol/Playwright/e2e lanes.
- Disable runtime Google Fonts fetching in tests via `test/flutter_test_config.dart`.

## Current Coverage Shape

Stable lanes:
- Parser tests.
- Firestore service tests with fake Firestore.
- Investment CGT calculator tests.
- Small screen smoke and validation tests.
- Export and utility tests.

Removed from `flutter test` because they were CI-flaky on Flutter 3.44:
- Long Investment CGT widget e2e journey.
- Worksheet interaction widget tests.
- Home upload-to-worksheet widget journey tests.

If these flows need coverage again, rebuild them as:
- Smaller tests with `Key(...)` lookups, not layout/text hit-testing.
- Service-level tests for save/calculate behavior.
- Browser e2e tests in a separate CI job.

## Test Design Rules

- Use fake services instead of Firebase network calls.
- Use synthetic PDF text and bytes unless testing a local gated fixture.
- Avoid assertions that depend on text wrapping or font metrics.
- Prefer `find.byKey` for critical controls in new tests.
- Reset global test state such as `FilePicker.platform` and draft queues in `tearDown`.

## Verification Commands

Default:

```bash
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

Focused examples:

```bash
flutter test test/services/investment_cgt_calculator_test.dart
flutter test test/services/commsec_trade_confirmation_parser_test.dart
flutter test test/screens/investment_cgt_module_test.dart
```
