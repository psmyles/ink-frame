# central/directory

Which frames each Google or Apple account is on, so signing in on a new device finds
them without a link or another device (app-flow §1.4). A Cloudflare Worker with a D1
(SQLite) database, on Cloudflare's free plan. Contract: [shared/api/directory.yaml](../../shared/api/directory.yaml).

It also has `POST /v1/supabase-oauth/token`, for the setup wizard's "Connect Supabase":
Supabase needs the OAuth App's client secret to exchange the code and to refresh tokens
(docs/spikes/c-supabase-oauth.md), so the app sends the code and PKCE verifier (later
the refresh token) here, and the Worker adds the secret. It stores and logs nothing.

## What it keeps

| Table | Columns | Notes |
|---|---|---|
| `frames` | account, url, key, added_at | `account` = SHA-256 of `google:<sub>` / `apple:<sub>`. `url`/`key` = the frame's address, the same pair invite links carry (not secret) |
| `tokens` | hash, account, created_at, used_at | SHA-256 of each device token. 20 newest per account; unused for 400 days → deleted by the daily cron |

No names, emails, photos or secrets. The OAuth client secret is a Worker secret
(`SUPABASE_OAUTH_CLIENT_SECRET`), not in the repo. ID tokens are checked against Google's and
Apple's published keys, and their audience against `shared/oauth-clients.json`
(bundled at deploy time).

If it's down, signing in on a new device (a link still works), "Connect Supabase" and
renewing an owner's Supabase connection stop working; frames and devices already
signed in never call it.

## Free plan

Workers: 100,000 requests a day. D1: 5 million rows read and 100,000 written a day,
5 GB in total (500 MB per database). A sign-in is a few rows; nothing here gets near
the limits at family scale.

## Commands

From this folder, with Wrangler pinned (the developer's `npx wrangler login`; nothing
is stored in the repo):

```sh
deno test --allow-read .                                         # routes and ID tokens, against SQLite
npx wrangler@4.146.0 d1 migrations apply ink-frame-directory --remote   # schema changes
npx wrangler@4.146.0 deploy                                      # the Worker
grep '^SUPABASE_OAUTH_CLIENT_SECRET=' ../../backend/.env.local | cut -d= -f2- | tr -d '\n' \
  | npx wrangler@4.146.0 secret put SUPABASE_OAUTH_CLIENT_SECRET  # once (or after regenerating it)
npx wrangler@4.146.0 dev --local                                 # run it locally (after `… migrations apply … --local`)
npx wrangler@4.146.0 tail                                        # live logs
```

Before release, give it a custom domain (e.g. `directory.psmyles.com`) so the host
can change later without an app update; the app reads it from `DIRECTORY_URL`.
