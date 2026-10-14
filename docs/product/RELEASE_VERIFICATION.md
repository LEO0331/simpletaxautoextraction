# Release verification

The Pages deployment workflow now calls the reusable CI workflow for the same checked-out commit. Deployment waits for strict analysis, the complete Flutter test suite, genuine Firestore emulator rules checks, and a real headless Chrome integration test. Both workflows pin Flutter 3.47.2. A failing verification job prevents Pages deployment.

The browser test uses the existing `integration_test` SDK dependency and creates a synthetic account in the local Authentication emulator. It opens the actual application, signs in through the form, saves a section review and reviewed salary item, checks Firestore persistence, changes another source to verify the stale-workpaper guard, reloads, changes tax years, and verifies that signing out removes the prior account's workpaper. It also records required missing fund evidence in the document inventory and signs out through the home button. It never loads production Firebase configuration.

## Run locally

Install Firebase CLI 14.11.2 as a test tool, start a matching ChromeDriver on port 4444, and run:

```sh
firebase emulators:exec --project demo-phase1 --config firebase.release.json --only auth,firestore 'make e2e-web'
```

Without Make (including Windows), replace `make e2e-web` with `flutter drive --driver=test_driver/release_browser_test.dart --target=integration_test/release_browser_test.dart -d web-server --browser-name=chrome --headless --web-port=7357`. ChromeDriver must already be running with `chromedriver --port=4444`; Flutter and Java must be on the path.

The config binds Auth to 127.0.0.1:9099 and Firestore to 127.0.0.1:8186. The demo project has no production resources. Do not substitute a production project. Tests create only synthetic values; PDFs and tax records are not used. Existing application dependencies remain unchanged. CLI/browser tooling is installed under ignored `build/release-tools` in CI.

For rules-only checks, run `python3 scripts/test_firestore_rules.py` against the local Firestore emulator. The script resets its demo database, so run it before browser tests rather than concurrently.

## Production boundary

Local emulator verification proves the checked-in rules and application workflow, not that a particular live Firebase deployment contains those rules. `python3 scripts/verify_public_release.py` checks the public Pages landing page, exact base path and build assets without signing in; deployment runs it after publishing. No production account, production writes, Firebase rule deployment, PR creation, or merge is part of these tests. The repository owner creates and merges the PR and deploys the reviewed rules alongside the client.

Official setup references: [Flutter browser integration testing](https://docs.flutter.dev/testing/integration-tests), [Auth emulator](https://firebase.google.com/docs/emulator-suite/connect_auth), and [Firestore emulator](https://firebase.google.com/docs/emulator-suite/connect_firestore).
