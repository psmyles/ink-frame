# Spike (c): Supabase OAuth App with PKCE

**Date:** 2026-10-03 · **Result:** works, but the token exchange **needs the client secret**, so it goes through the developer's Cloudflare Worker (`central/`), not the app.

Script: `tools/dev/oauth-connect.ts` (authorization code + PKCE, loopback redirect `http://localhost:53682/callback`). OAuth App "Ink Frame" registered by the developer in org `psmyles` with read/write on every permission offered; client ID and secret in `backend/.env.local`.

## Findings

| Step | Result |
|---|---|
| Consent in the browser (`/v1/oauth/authorize`, PKCE S256) | ✅ the account chooses an organization and approves; the code comes back to the loopback redirect |
| Code exchange **without** `client_secret` (PKCE only) | ❌ `422 {"message":"Required parameter: client_secret"}` |
| Code exchange with the secret (HTTP Basic) | ✅ access token (valid **24 h**) + refresh token |
| `GET /v1/organizations`, `GET /v1/projects` with the OAuth token | ✅ (`psmyles`; `ink-frame`) |
| Refresh with the secret | ✅ new access + refresh token |
| A **second account outside** the `psmyles` org (new free account, private window) | ✅ approves the app as it is (not published); the token sees only that account's own org and its (no) projects; refresh works |

## Consequences

- The secret can't ship in the app (anyone could extract it). The app does the PKCE consent itself and sends the **code + verifier** (later the **refresh token**) to a token-exchange route on the Cloudflare Worker, which adds the secret (a Worker secret) and forwards to `https://api.supabase.com/v1/oauth/token`. It stores and logs nothing. PKCE still protects the code: it's useless without the verifier, which stays on the device until the exchange.
- Access tokens last 24 h, so owner tools (wake up, upgrade, delete) refresh through the same route.
- Any Supabase account can approve the app as registered; no publishing step is needed (tested with a second, unrelated account). A token only reaches the organization the person chose.
- The OAuth App needs both callback URLs from `shared/oauth-clients.json` registered: `http://localhost:53682/callback` (Windows, Linux, this script) and `https://psmyles.github.io/ink-frame/oauth/` (phones and Macs, which forward to `inkframe://supabase-oauth`). Supabase checks it before the sign-in page: an unregistered one gets `422 {"message":"redirect_uri not allowed"}`.
- Scopes: every permission granted for now; trim once the wizard's calls are known (§6.2: projects, database query, functions deploy, auth config, API keys, restore).
