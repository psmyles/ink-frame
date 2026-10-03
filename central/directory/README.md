# central/directory

Which frames each Google or Apple account is on, so signing in on a new device finds
them without a link or another device (app-flow §1.4). A Cloudflare Worker with a D1
(SQLite) database, on Cloudflare's free plan. Contract: [shared/api/directory.yaml](../../shared/api/directory.yaml).

## What it keeps

| Table | Columns | Notes |
|---|---|---|
| `frames` | account, url, key, added_at | `account` = SHA-256 of `google:<sub>` / `apple:<sub>`. `url`/`key` = the frame's address, the same pair invite links carry (not secret) |
| `tokens` | hash, account, created_at, used_at | SHA-256 of each device token. 20 newest per account; unused for 400 days → deleted by the daily cron |

No names, emails, photos or secrets. ID tokens are checked against Google's and
Apple's published keys, and their audience against `shared/oauth-clients.json`
(bundled at deploy time).

If it's down, only signing in on a new device stops working (a link still does);
frames and devices already signed in never call it.

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
npx wrangler@4.146.0 dev --local                                 # run it locally (after `… migrations apply … --local`)
npx wrangler@4.146.0 tail                                        # live logs
```

Before release, give it a custom domain (e.g. `directory.psmyles.com`) so the host
can change later without an app update; the app reads it from `DIRECTORY_URL`.
