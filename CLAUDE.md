# CLAUDE.md

Ink Frame: a Flutter companion app, a per-family Supabase backend, and ESP32-S3 e-ink frame firmware.

**[PLAN.md](PLAN.md) is the single source of truth.** Read it before doing any work.

## Rules
- Work in the phase order in PLAN.md §0. Phase 1 and Phase 2 are gates that need the user; don't start the phase after a gate until the user has finished it.
- When you finish an item, tick it in PLAN.md §13 (Progress checklist).
- If an assumption in PLAN.md §14 (Verify list) turns out differently, update the plan in the same change and add an entry to §16 (Decision log).
- **Never commit secrets.** The Supabase access token, keys and passwords go in `.env.local` files (gitignored) or in session environment variables (`SUPABASE_ACCESS_TOKEN`).
- `reference/` is read-only. It is the spec the new code is ported from (see `reference/README.md`).
- `shared/api/openapi.yaml` is the contract for `device-api` and `app-api`. Change the contract first, then the code on both sides.

## Layout
See PLAN.md §4. In brief: `shared/` (presets, API contract, test vectors), `backend/supabase/` (migrations, Edge Functions, tests), `app/` (Flutter), `firmware/` (PlatformIO), `tools/` (golden vectors, frame simulator, dev scripts), `central/` (firmware feed), `docs/`.

## Commands
- `deno run --allow-read --allow-write tools/dev/gen-seed.ts`: regenerate `backend/supabase/seed.sql` after editing `shared/presets.json`.
- `deno run --allow-read --allow-net --allow-env tools/dev/migrate.ts [--status]`: apply pending migrations and the seed to the dev project (reads `backend/.env.local`).
- New tables or functions in `public` get no client privileges by default (0002 revokes them); grant `SELECT` explicitly where members need to read.
- `set -a; . backend/.env.local; set +a; supabase functions deploy device-api app-api --project-ref "$SUPABASE_PROJECT_REF" --use-api --workdir backend`: deploy the Edge Functions (no Docker needed).
- `deno run --allow-read --allow-write tools/dev/gen-tz.ts`: regenerate `functions/_shared/tz.ts` from the system tzdata.
- Pin `npm:` versions in the functions to releases at least 24 h old; Deno refuses newer ones by default.
- `deno test --allow-net --allow-env --allow-read backend/supabase/tests/`: integration tests against the project in `backend/.env.local` (~90 s; cleans up after itself; skips if the project already has an admin).
