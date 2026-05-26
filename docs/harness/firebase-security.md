# Firebase Security Harness

Source: The app stores user tax and investment records in Firestore and relies on Firebase Auth for isolation.
Trigger: Read when editing Firestore schema, `FirestoreService`, `firestore.rules`, auth behavior, or Firebase console settings.
Expiry: Revise when backend storage moves away from Firebase.

## Data Isolation

All user-owned data should be scoped under:

```text
users/{userId}/...
```

Rules must require:

```text
request.auth != null && request.auth.uid == userId
```

Current collections:
- `users/{userId}/tax_records/{recordId}`
- `users/{userId}/properties/{propertyId}`
- `users/{userId}/settings/mappings`
- `users/{userId}/investment_transactions/{transactionId}`

## Rules Standards

- Reject unknown fields with `keys().hasOnly(...)` on writes.
- Validate required fields with `keys().hasAll(...)` where appropriate.
- Validate numeric ranges and string length caps.
- Separate `allow read` from write validation when rules need `request.resource.data`.
- Avoid broad `allow read, write` blocks for nested user data.
- Deletes should be explicit; deny deletes for settings unless there is a product reason.

## Client Auth Notes

- Web Firebase Auth persistence should remain session-scoped unless product requirements change.
- Firebase client API keys in `firebase_options.dart` are public client configuration, not private secrets.
- Private Firebase files such as platform service config files should stay gitignored.

## Verification

Run:

```bash
flutter test test/services/firestore_service_test.dart
flutter test test/services/firestore_service_extended_test.dart
flutter analyze --fatal-infos --fatal-warnings
```

Before release, also follow:

```text
docs/PRODUCTION_HARDENING_CHECKLIST.md
```
