# Spike (a): Management API coverage with a personal access token

**Date:** 2026-09-25 · **Result:** everything the setup wizard needs is available, and a project created entirely through the API passes the full backend test suite.

Method: `tools/dev/provision.ts` created a throwaway project (`inkframe-spike`) in the spare free slot, applied the migrations, deployed the functions and configured auth, all through `api.supabase.com`. The integration tests then ran against it, followed by pause, restore and delete.

## Wizard steps (PLAN.md §6.2)

| Step | Endpoint | Result |
|---|---|---|
| List orgs | `GET /v1/organizations` | ✅ Needs an org-wide token (a project-scoped PAT returns `[]`) |
| Create project | `POST /v1/projects` `{name, organization_slug, db_pass, region_selection: {type: "specific", code}}` | ✅ `region` and `organization_id` are deprecated in favour of `region_selection` and `organization_slug`. `region_selection` also accepts `{type: "smartGroup", code: "americas" \| "emea" \| "apac"}` |
| Wait until ready | `GET /v1/projects/{ref}` (status) + `GET /v1/projects/{ref}/health?services=db,auth,rest,storage` | ✅ **Healthy after ~4 s**, not the 1–2 min assumed. Keep the progress screen anyway; this may vary |
| Apply migrations | `POST /v1/projects/{ref}/database/query` | ✅ Runs as `postgres`; a multi-statement `begin … commit` works, so each migration and its `schema_version` row are atomic. All 5 migrations + seed: ~8 s |
| Deploy functions | `POST /v1/projects/{ref}/functions/deploy?slug=…` (multipart: `metadata` JSON + `file` parts) | ✅ Server-side bundling. Upload the **source files** with paths relative to `functions/` (e.g. `device-api/index.ts`, `_shared/http.ts`) and `metadata = {entrypoint_path, name, verify_jwt: false}`. No eszip or Docker. Both functions: ~5 s |
| Configure auth | `PATCH /v1/projects/{ref}/config/auth` | ✅ See spike (b) |
| Get keys | `GET /v1/projects/{ref}/api-keys?reveal=true` | ✅ Returns legacy `anon`/`service_role` and new `publishable`/`secret` keys |

End to end: **17 s** from `POST /v1/projects` to a configured project.

## Limits and failures

- **Free plan, 2 active projects:** confirmed. A third create returns **400** with: *"The following organization members have reached their maximum limits for the number of active free projects within organizations where they are an administrator or owner: psmyles (2 project limit). To continue, these users will need to either delete, pause or upgrade one or more of these projects."* The wizard can match on `"2 project limit"` / `"maximum limits"` and explain.

## Pause and restore (PLAN.md §6.4)

| | Endpoint | Result |
|---|---|---|
| Pause | `POST /v1/projects/{ref}/pause` | `PAUSING` → `INACTIVE` in ~67 s |
| While paused | any Edge Function call | **HTTP 540** `Project paused. Please unpause the project before proceeding.` The app can detect a pause from this status alone |
| Restore | `POST /v1/projects/{ref}/restore` `{}` | `COMING_UP` → `RESTORING` → `ACTIVE_HEALTHY` in **~2 min 47 s**. Functions answered 500 for a few seconds after that, then normally |
| After restore | — | Schema version, both cron jobs and seed data intact |

`GET /v1/projects/{ref}/restore` lists available Postgres versions for the restore.

## Usage

- `GET /v1/projects/{ref}/analytics/endpoints/usage.api-counts?interval=1day` gives **hourly request counts** per service (auth, REST, storage, realtime).
- There is **no storage-size or egress endpoint**. Storage is computed from the database (`GET /app-api/usage`); egress can't be shown.

## Other endpoints of note

- `DELETE /v1/projects/{ref}`: deletes a project (used for "delete the whole family space").
- `GET /v1/projects/{ref}/functions`: lists functions with `version` and `verify_jwt`.
- `POST /v1/projects/{ref}/database/query/read-only`: read-only SQL, useful for the member-side schema-version check if ever needed.
- No endpoint creates OAuth Apps; they're registered in the dashboard (spike c).
