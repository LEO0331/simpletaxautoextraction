# Release Harness

Source: The app is published as Flutter Web on GitHub Pages and uses Firebase services.
Trigger: Read when editing deployment workflows, `web/`, SEO metadata, Firebase release settings, or pre-release checklists.
Expiry: Revise if hosting moves away from GitHub Pages.

## Deployment Constraints

- Preserve the GitHub Pages base path: `/simpletaxautoextraction/`.
- Do not break static asset loading for Flutter Web.
- Keep SEO/static metadata edits limited to `web/` unless changing app routing intentionally.
- Do not commit generated secrets or local Firebase private config.

## Pre-Release Checks

Run:

```bash
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter build web --release --base-href /simpletaxautoextraction/
```

Then follow:

```text
docs/PRODUCTION_HARDENING_CHECKLIST.md
```

## Firebase Console Checks

Before first production release or major auth/storage changes:
- Confirm authorized domains.
- Enable and monitor App Check where supported.
- Review password policy and abuse protections.
- Publish current `firestore.rules`.
- Confirm no permissive test rules are active.

## SEO Notes

Flutter Web is client-rendered, so SEO improvements should focus on:
- Correct title and meta description in `web/index.html`.
- `robots.txt` and `sitemap.xml`.
- Canonical production URL.
- Stable landing-page copy visible before heavy app interaction where possible.
