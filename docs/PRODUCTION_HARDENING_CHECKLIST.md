# Firebase Production Hardening + Publish Checklist (One Page)

Last reviewed: 2026-04-01 (Asia/Taipei)

Use this on release day for the production Firebase project.

## A) Critical Console Hardening (do first)

### 1) App Check (Firebase Console -> Build -> App Check)

- [ ] Web app registered with **reCAPTCHA Enterprise** provider.
- [ ] Allowed domains in reCAPTCHA include only production hostnames.
- [ ] Token TTL set (default 1 hour is acceptable for launch).
- [ ] Start in monitor mode, then enforce after clean metrics window.
- [ ] Enforced for:
  - [ ] Cloud Firestore
  - [ ] Cloud Storage (if used)

Sign-off: _________  Date: _________

### 2) Authorized Domains (Firebase Console -> Authentication -> Settings)

- [ ] Keep only required production domains.
- [ ] Remove `localhost` after release (unless explicitly needed).
- [ ] Confirm exact redirect domain match for OAuth providers.

Sign-off: _________  Date: _________

### 3) Password Policy (Firebase Console -> Authentication -> Settings -> Password policy)

- [ ] Minimum length set to at least 10.
- [ ] Require complexity (upper/lower/number/symbol) per product UX decision.
- [ ] Rollout mode:
  - [ ] `Notify` first (existing user migration), then
  - [ ] `Require` after communication window.
- [ ] Email enumeration protection enabled.

Sign-off: _________  Date: _________

### 4) Abuse Protections (Firebase + Google Cloud Console)

- [ ] Auth rate limits and suspicious spikes monitored.
- [ ] Budget and usage alerts configured (Auth, Firestore, Hosting).
- [ ] Alert on sudden signup spike and sign-in failure spike.
- [ ] Alert on Firestore permission-denied spike.
- [ ] Alert on App Check rejected requests spike.
- [ ] If phone auth is enabled: SMS region policy configured.

Sign-off: _________  Date: _________

## B) Project Security Baseline

- [ ] Production uses a dedicated Firebase project.
- [ ] `firestore.rules` from this repo are published.
- [ ] Principle of least privilege applied to IAM roles.
- [ ] MFA enforced for all console admins.
- [ ] No stale members or unused service account keys.

Sign-off: _________  Date: _________

## C) App + Web Publish Readiness

- [ ] `web/index.html` metadata live (title/description/OG/Twitter/canonical).
- [ ] `web/robots.txt` and `web/sitemap.xml` deployed.
- [ ] `web/.well-known/security.txt` deployed and monitored.
- [ ] HTTPS-only hosting confirmed.
- [ ] Smoke test: sign-up, sign-in, upload, save, reload, compare.

Sign-off: _________  Date: _________

## D) Go/No-Go Gate

- [ ] No P0/P1 bugs open.
- [ ] `flutter analyze` and `flutter test` pass on release commit.
- [ ] Rollback plan and owner confirmed.

Release owner: _________  Decision: GO / NO-GO  Time: _________

## Official references

- App Check overview: https://firebase.google.com/docs/app-check
- App Check web (reCAPTCHA Enterprise): https://firebase.google.com/docs/app-check/web/recaptcha-enterprise-provider
- App Check enforcement: https://firebase.google.com/docs/app-check/enable-enforcement
- Firebase Auth password policy: https://firebase.google.com/docs/auth/web/password-auth
- Firebase Auth limits: https://firebase.google.com/docs/auth/limits
- Auth blocking events: https://firebase.google.com/docs/functions/auth-blocking-events
- Firebase support FAQ: https://firebase.google.com/support/faq
