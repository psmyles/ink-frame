# Spike (b): Google and Apple providers without secrets

**Date:** 2026-09-25 · **Result:** config part confirmed; the sign-in part needs real client IDs (Phase 3).

## Config (confirmed)

`PATCH /v1/projects/{ref}/config/auth` accepts, with **no secret**:

```json
{
  "external_google_enabled": true,
  "external_google_client_id": "<ios>",
  "external_google_additional_client_ids": "<android>,<web>,<desktop>",
  "external_apple_enabled": true,
  "external_apple_client_id": "<bundle id>",
  "external_email_enabled": false
}
```

Read back, Supabase **merges** the additional IDs into `external_google_client_id` as one comma-separated list and returns `external_google_additional_client_ids: null`. All four IDs are kept. The wizard can send the full comma-separated list in `external_google_client_id` directly.

`external_google_secret` and `external_apple_secret` stay `null`. Turning `external_email_enabled` off works.

Other fields available: `external_google_skip_nonce_check` (may be needed if the iOS Google SDK can't pass a nonce), `external_{google,apple}_email_optional`, `disable_signup`.

## Still to verify (needs real client IDs, Phase 3a)

- `signInWithIdToken` succeeds for an ID token from each client (iOS, Android, desktop loopback) with no secret configured.
- Apple native sign-in on iOS/macOS with only the bundle ID.
- Whether iOS `google_sign_in` needs `skip_nonce_check`.
