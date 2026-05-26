# Harness Router

This project uses a lightweight harness layer so future agents do not need to load one giant instruction file before every task. The router stays short; task-specific details live in topical docs under `docs/harness/`.

## Project Snapshot

Flutter Web app for Australian tax record extraction and investment CGT estimation.

Core domains:
- Property tax worksheet extraction from PDF statements.
- Investment CGT tracker for broker trade confirmations.
- Firebase Auth and Firestore user-scoped persistence.
- Static Flutter Web deployment to GitHub Pages.

## Quick Commands

Run these before claiming completion:

```bash
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

Optional browser smoke lane:

```bash
make e2e-web
```

## Global Hard Constraints

- Do not commit personal PDFs, broker confirmations, Firebase private config files, or local runtime state.
- Do not store investment share transactions as `TaxRecord`; use the investment models.
- Do not claim tax advice. Use estimate-only wording for CGT features.
- Firestore writes must remain scoped to `users/{userId}/...` and rules must enforce `request.auth.uid == userId`.
- Keep `flutter test` deterministic. Browser-style journey tests belong in a separate e2e lane.
- Preserve GitHub Pages base-path behavior when editing web/deploy code.
- Prefer small, behavior-preserving diffs and run verification before reporting success.

## Routing Table

Read only the document relevant to the current task.

| Task type | Read |
| --- | --- |
| Adding or changing Investment CGT features | [Investment CGT Harness](harness/investment-cgt.md) |
| Editing PDF extraction or parser logic | [PDF Parsing Harness](harness/pdf-parsing.md) |
| Firestore, auth, rules, Firebase console hardening | [Firebase Security Harness](harness/firebase-security.md) |
| Writing or fixing tests and CI failures | [Testing Harness](harness/testing.md) |
| Release, deploy, SEO, GitHub Pages | [Release Harness](harness/release.md) |
| Adding/changing agent instructions | [Instruction Governance](harness/instruction-governance.md) |

## Instruction Lifecycle

Each harness instruction should have:
- Source: why this instruction exists.
- Trigger: when an agent should read it.
- Expiry: when it can be deleted or revised.

If a rule applies only to one workflow, move it into that workflow doc instead of adding it here.

## Source

This layer follows the harness-engineering principle that the entry file should be a short router, not an encyclopedia. The linked lecture recommends keeping common information nearby, moving occasional information into topic docs, and using progressive disclosure to improve signal-to-noise ratio.
