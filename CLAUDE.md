# CLAUDE.md

Ink Frame: a Flutter companion app, a per-family Supabase backend, and ESP32-S3 e-ink frame firmware.

**[PLAN.md](PLAN.md) is the single source of truth.** Read it before doing any work.

## Rules
- Work in the phase order in PLAN.md §0. Phase 1 and Phase 2 are gates that need the user; don't start the phase after a gate until the user has finished it.
- When you finish an item, tick it in PLAN.md §13 (Progress checklist).
- If an assumption in PLAN.md §14 (Verify list) turns out differently, update the plan in the same change and add an entry to §16 (Decision log).
- **Never commit secrets.** The Supabase access token, keys and passwords go in `.env.local` files (gitignored) or in session environment variables (`SUPABASE_ACCESS_TOKEN`).
- `reference/` is read-only. It is the spec the new code is ported from (see `reference/README.md`).
- `shared/api/openapi.yaml` is the contract for `device-api` and `app-api`, `shared/api/directory.yaml` for the directory. Change the contract first, then the code on both sides.
- **One Supabase project = one frame.** User-facing words: frame, owner, people, "checks for new photos", "connect the frame"; never space, project, admin or sync (PLAN.md §2).

## Layout
See PLAN.md §4. In brief: `shared/` (presets, API contract, test vectors), `backend/supabase/` (migrations, Edge Functions, tests), `app/` (Flutter), `firmware/` (PlatformIO), `tools/` (golden vectors, frame simulator, dev scripts), `central/` (firmware feed), `docs/`.

## Commands
- `deno run --allow-read --allow-write tools/dev/gen-seed.ts`: regenerate `backend/supabase/seed.sql` after editing `shared/presets.json`.
- `deno run --allow-read --allow-net --allow-env tools/dev/migrate.ts [--status]`: apply pending migrations and the seed to the dev project (reads `backend/.env.local`).
- New tables or functions in `public` get no client privileges by default (0002 revokes them); grant `SELECT` explicitly where members need to read.
- `set -a; . backend/.env.local; set +a; supabase functions deploy device-api app-api --project-ref "$SUPABASE_PROJECT_REF" --use-api --workdir backend`: deploy the Edge Functions (no Docker needed).
- `deno run --allow-read --allow-write tools/dev/gen-tz.ts`: regenerate `functions/_shared/tz.ts` and the app's `lib/data/timezones.dart` from the system tzdata.
- Pin `npm:` versions in the functions to releases at least 24 h old; Deno refuses newer ones by default.
- `deno run --allow-all tools/dev/sim-scenario.ts`: the §12.1 scenario with the real `frame_sim` against the dev project (same owner requirement as the tests).
- `deno run --allow-read --allow-net --allow-env tools/dev/reset-dev.ts --yes`: drop and re-apply all migrations on the dev project (unreleased migrations only).
- `deno test central/tests/`: link parsing for the `central/site` pages (published to GitHub Pages by `.github/workflows/pages.yml`).
- `deno run --allow-read --allow-write tools/dev/bundle-backend.ts [--check]`: copy the migrations, seed, functions, model list and sign-in settings into `app/assets/backend/` (what the setup wizard installs). Run after changing `backend/supabase/` or `shared/presets.json`; the app's tests fail when it's stale.
- `deno run --allow-all tools/dev/provision-live-test.ts`: the app's setup-wizard steps against the real Management API (creates a project in the spare slot, signs in as owner, deletes it; ~35 s).
- `deno run --allow-read --allow-net --allow-env --allow-run tools/dev/oauth-connect.ts [--print-url]`: "Connect Supabase" by hand, through the Worker (opens the browser; tokens never printed).
- `deno test --allow-read central/directory/`: the directory Worker against SQLite. Deploy from `central/directory/` with `npx wrangler@4.146.0 d1 migrations apply ink-frame-directory --remote` then `npx wrangler@4.146.0 deploy` (the user's `wrangler login`; contract `shared/api/directory.yaml`).
- `cd app && flutter test`: app tests without network (incl. golden parity for `lib/imaging`). `node tools/golden/gen-vectors.mjs`: regenerate `shared/test-vectors/dither.json` from the reference. `deno run --allow-all tools/dev/app-live-test.ts`: the app's data layer against the dev project. More in `app/README.md`.
- `deno run --allow-read --allow-net --allow-env tools/dev/auth-providers.ts [--check]`: turn on Google/Apple sign-in on the dev project with the client IDs in `shared/oauth-clients.json` (provision.ts uses the same file).
- `deno run --allow-read --allow-net --allow-env tools/dev/dev-frame.ts [--invite | --remove]`: a frame on the dev project to join in the app (the backend tests skip while it exists). `--owner-login` (needs `--allow-write`) lets you sign in as its owner in developer mode; the password goes into `backend/.env.local` as `DEV_OWNER_PASSWORD`, never to the terminal.
- `cd tools/frame_sim && dart test`: frame_sim unit tests. Run the simulator with `dart run bin/frame_sim.dart --help`.
- `deno run --allow-read --allow-net --allow-env tools/dev/provision.ts --name <n> [--keep-email]` / `delete-project.ts --ref <ref> --yes`: throwaway projects in the spare free slot.
- `deno test --allow-net --allow-env --allow-read backend/supabase/tests/`: integration tests against the project in `backend/.env.local` (~100 s; sets up the project's frame itself, cleans up after itself; skips if the project already has a real owner).
