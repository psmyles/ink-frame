# Ink Frame: Master Plan

> **Status:** Planning complete for the backend and the overall system. Planning for the Flutter UI and flow is **deliberately deferred** to Phase 2.
> **Owner:** Chandan Singh · **Last updated:** 2026-09-25
> **Reference sources:** `reference/ink-frame-lab/` (see `reference/README.md`)

---

## 0. How to use this document

This is the single source of truth for building Ink Frame. Work goes in **phases**, and some phases are **gates** that need the user's input before code is written.

| Phase | What | Who | Gate? |
|---|---|---|---|
| 0 | Repo scaffold | Claude | – |
| 1 | Supabase account + access token | **User** | ✅ must finish before Phase 1B |
| 1B | Backend package + dev project + Management API spikes + frame simulator | Claude | – |
| 2 | **Flutter app flow and UI structure planning session** (no code) | User + Claude | ✅ must finish before Phase 3 |
| 3 | Flutter app (iOS, Android, **desktop**) | Claude | – |
| 4 | Firmware (PlatformIO) + BLE pairing + OTA feed | Claude (+ user with hardware) | – |
| 5 | Hardening + store release | User + Claude | – |

Rules for any Claude session working here:
- Read this file and `CLAUDE.md` first. Check off items in §13 (Progress checklist) as you finish them.
- **Never commit secrets.** Access tokens, keys and passwords go in `.env.local` files, which are gitignored, or in session environment variables.
- Treat `reference/` as read-only.
- If an item in §14 (Verify list) turns out differently than assumed, update this plan in the same change and note it in §16 (Decision log).

---

## 1. Context and goals

The existing product ([ink-frame-lab](https://github.com/psmyles/ink-frame-lab)) is a web tool that crops and dithers images for e-ink displays. It is paired with a standalone firmware for the **Seeed reTerminal E1002** (ESP32-S3, 7.3" Spectra 6, 800×480). Today that firmware reads `/images/1.png…N.png` from an SD card. Photos get there when the user holds the green button, joins the frame's own Wi-Fi hotspot, and uploads PNGs made in the web tool. That's clunky: two tools, switching Wi-Fi networks, and it has to be done in person at the frame.

**Ink Frame** replaces that with:
- A **native Flutter companion app** (iOS, Android, and fully functional on **desktop** for easy testing). It crops, dithers and compresses photos **on the device** and uploads them to the **family's own Supabase project** (free tier).
- **Frames** sync daily (or when the green button is pressed). They mirror the family's cloud photos onto the SD card, which acts only as a cache, and show them offline as today.
- An **in-app wizard** that sets up each family's Supabase project automatically. Families need only a Supabase account (one admin) and a Google/Apple login (everyone).

---

## 2. Decisions made

| Topic | Decision |
|---|---|
| Audience | Consumer product for other people |
| Backend tenancy | **One Supabase project per family**, on the family's own free-tier account. The family's limits are not shared with other families |
| Project setup (production) | **In-app wizard** via Supabase OAuth + Management API. It creates the project, schema, buckets, functions and auth config |
| Project setup (development) | Developer **Personal Access Token (PAT)** with the Supabase CLI and Management API. The wizard's API client accepts a PAT or an OAuth token through one interface |
| Login | **Sign in with Google + Sign in with Apple** through native ID-token sign-in, using the developer's OAuth client IDs. Families never touch OAuth consoles (§5). Anonymous sign-in was considered and **rejected**: social login lets members recover access on a new device just by signing in again |
| Display names | Typed by the user when joining a family space (not taken from the Google/Apple profile), and editable later |
| Users within a project | Full multi-user: any project member can pair frames and invite others per frame |
| Sharing | Frame owner invites members. Members delete their own photos; the owner can delete anything |
| App | Native Flutter, **no webview**. Dithering ported to Dart; output PNG compressed (indexed palette) |
| App platforms | **iOS + Android** (store targets) + **desktop** (Windows required as the developer's machine; macOS/Linux nice-to-have), with desktop fully functional for testing |
| Frame onboarding | **BLE** from the app: Wi-Fi details + family API URL + pairing token |
| Sync | Fixed schedule (default 24 h) + **short green-button press = sync now** |
| Deletes | Frame **mirrors the cloud exactly** |
| Offline/hotspot mode | **Removed.** No soft-AP and no web server; the SD card is only a cache |
| Settings synced from the cloud | Image change interval, display order, sync interval, quiet hours |
| Limits | Stay within the Supabase free tier. The app shows usage. Optional per-frame/per-user quotas come from a config table (values TBD) |
| Hardware | Supports many models (model → resolution/palette from a table); **E1002 first** |
| Originals | **Only the processed PNG** is uploaded |
| OTA | **Yes, in v1**, from a **central public, signed** release feed (not stored in family projects) |
| Firmware toolchain | **PlatformIO + Arduino framework** |
| Repo | This monorepo (`psmyles/ink-frame`). ink-frame-lab stays a standalone web tool |
| Build order | Supabase account/token → backend → **Flutter planning session** → Flutter app → firmware |

---

## 3. Architecture overview

```
                ┌──────────────── developer-run (central, tiny, stateless) ─────────────────┐
                │  • Firmware feed: GitHub Releases assets + signed manifest.json (Pages)    │
                │  • (only if required, see §14) Supabase-OAuth token-exchange endpoint      │
                └────────────────────────────────────────────────────────────────────────────┘

 Admin's app ──Supabase OAuth (prod) / PAT (dev)──► Supabase Management API ──creates/configures──┐
                                                                                                   ▼
 Flutter app ──Google/Apple ID token──►  FAMILY SUPABASE PROJECT (free tier)
   pick → crop → dither → indexed PNG     • Auth: Google/Apple providers using our client IDs
   ├──► app-api Edge Function ──────────► • Postgres: members, frames, images, settings, quotas
   │       └ signed upload URL ─────────► • Storage bucket: frame-images (private)
   └──BLE: Wi-Fi + API URL + pairing token──► Frame

 Frame (ESP32-S3) ──HTTPS + device secret──► device-api Edge Function (claim, sync)
                  ──HTTPS──► central firmware feed (OTA; signature checked on the device)

 tools/frame_sim (Dart CLI) ── same device-api contract ── stands in for the frame before Phase 4
```

**Swappability rule:**
- The frame knows only an `api_base_url` (delivered over BLE) and the JSON contract in `shared/api/openapi.yaml`. Storage reaches it only as opaque signed URLs.
- The app uses Supabase Auth directly, but all data access goes through Dart repository interfaces with Supabase implementations behind them.

---

## 4. Repository layout

```
ink-frame/
  PLAN.md                     this file
  CLAUDE.md                   session guidance (short; points here)
  reference/                  read-only copies from ink-frame-lab (see reference/README.md)
  shared/
    presets.json              devices + palettes (seed source; copied from reference)
    api/openapi.yaml          device-api + app-api contract
    test-vectors/             golden dithering inputs/outputs generated from the JS reference
  backend/supabase/
    config.toml
    migrations/               numbered SQL migrations (also bundled into the app for the wizard)
    functions/device-api/     Deno/TypeScript Edge Function
    functions/app-api/        Deno/TypeScript Edge Function (Hono router)
    functions/_shared/        shared TS (auth helpers, tz table, errors)
    seed.sql                  generated from shared/presets.json
    tests/                    Deno integration tests (RLS, functions, §12.1 scenario) against a dev project
  app/                        Flutter app (android/ ios/ windows/ macos/ [linux/])
  firmware/                   PlatformIO project
  tools/
    golden/                   Node script: runs reference dithering.js → shared/test-vectors
    frame_sim/                Dart CLI frame simulator (claim/sync/mirror/render)
    dev/                      dev scripts (upload test PNGs, reset dev project, bundle backend)
  central/                    firmware feed publishing (+ OAuth token-exchange fn if needed)
  docs/
    app-flow.md               ← produced by Phase 2
    spikes/                   findings from Phase 1B spikes
    auth.md, provisioning.md, sync-protocol.md, pairing.md, ota.md
  .github/workflows/          backend tests, app tests/builds, pio build, firmware release
  .gitignore                  must include .env*, build outputs, .dart_tool, .pio, supabase/.temp
```

---

## 5. Authentication and identity

### 5.1 Two kinds of tokens (keep them apart)
1. **Supabase platform token.** This is the admin's supabase.com account token: an OAuth token in production, a PAT in development. It controls the whole Supabase account: it can create or delete projects, run any SQL, and read keys.
   - Lives **only** on the admin's device, in secure storage.
   - Used only for provisioning, schema upgrades, restoring a paused project, and reading usage.
   - **Never** used as a member identity or sent to the frame.
2. **Project user token (JWT).** Issued by the family project's Supabase Auth after Google/Apple sign-in. Every app user has one. RLS and `app-api` authorize with it.

### 5.2 Native ID-token sign-in
1. The platform sheet (`google_sign_in` / `sign_in_with_apple`) returns an **ID token**. Its `aud` is *our* Google client ID or iOS bundle ID.
2. `supabase.auth.signInWithIdToken(provider, idToken, nonce)` runs against the **family** project.
3. Supabase checks the token's signature against Google's/Apple's public keys, and checks that `aud` is in the provider's allowed client IDs.
4. The wizard writes those client IDs into each family project through the Management API. Client IDs are not secrets (they ship inside the app).

### 5.3 Platform matrix
| Platform | Google | Apple |
|---|---|---|
| iOS | native (`google_sign_in`) | native (`sign_in_with_apple`), required by App Store rule 4.8 because Google is offered |
| Android | native (`google_sign_in`) | **not in v1** (the web flow needs a Services ID + a secret key that expires every 6 months) |
| macOS | `google_sign_in` (supported) | native `sign_in_with_apple` (supported) |
| **Windows / Linux** | **loopback OAuth + PKCE** with a Google "Desktop app" client ID: open the system browser, catch the redirect on `http://127.0.0.1:<port>`, exchange the code, take the `id_token`, then `signInWithIdToken`. Add the Desktop client ID to the allowed client IDs | not available natively. **Decide in Phase 2** (options: none on Windows; Apple web flow; dev-only email/password on dev projects) |

### 5.4 Membership gate
- Sign-in is open at the auth layer: anyone holding a project URL + anon key could create an auth user. **Everything** is therefore gated by a `project_members` row, which RLS and `app-api` both check.
- Rows are created by the wizard (admin) or by accepting an invite.
- A pg_cron job deletes auth users that have had no membership for more than 24 h.

### 5.5 Joining a family space
- **Invite payload:** `inkframe://join?u=<project_url>&k=<anon_key>&c=<invite_code>`, shared as a QR code or link. On desktop, pasting the link or code works too.
- **Join flow:** the app saves the project → the user signs in with Google/Apple → types a **display name** → `POST /invites/accept {code, display_name}`.
- The app keeps a **list of family spaces** (URL + anon key + session per space) and has a space switcher.

---

## 6. Family project provisioning

### 6.1 Developer one-time setup
- **Supabase:** register an **OAuth App** in the developer's Supabase org (dashboard only; no API) → client id. Callback URLs must be **HTTPS or localhost**, so: `http://localhost:<port>/callback` for desktop, and for mobile an HTTPS bounce page on the project's GitHub Pages site (next to the firmware feed) that forwards `code`/`state` to `inkframe://supabase-oauth`. Safe with PKCE: the code is useless without the verifier, which never leaves the device.
- **Google Cloud:** OAuth client IDs for **iOS, Android, Web, Desktop**.
- **Apple Developer:** App ID with Sign in with Apple.
- These IDs go in the app's build config (`app/lib/config/`, plus per-platform files). Nothing secret is embedded unless §14 forces it.

### 6.2 Wizard steps ("Set up a new family space")
1. **Connect Supabase:** authorization code + PKCE in the system browser. In dev, this is skipped by pasting a **PAT** (a dev-only setting).
2. **Choose or create an org and region → create the project** (`POST /v1/projects`, generated DB password kept in secure storage). Poll `GET /v1/projects/{ref}` and `/health?services=db,auth,rest,storage` until healthy (measured ~4 s; keep a progress screen in case it's slower).
   - The free plan allows **2 active projects per account**. If the limit is hit, show a clear message.
3. **Apply migrations:** run the bundled SQL from `backend/supabase/migrations/` through `POST /v1/projects/{ref}/database/query`, in order, recording `schema_version`. This creates tables, RLS, buckets and policies, cron jobs and seed data.
4. **Deploy the Edge Functions** `device-api` and `app-api` through the Management API's multipart deploy (`POST /v1/projects/{ref}/functions/deploy`): the app uploads the function **source files** it bundles as assets, and Supabase bundles them server-side (`tools/dev/deploy-functions.ts` is the reference).
5. **Configure auth** through `PATCH /v1/projects/{ref}/config/auth`:
   - enable Google (all our client IDs) and Apple (bundle ID)
   - turn off email signup
   - set the JWT expiry and site/redirect URLs if needed
6. Fetch the project URL + anon key → the admin signs in with Google/Apple → types a display name → becomes `project_members.role = admin`.
7. Keep the platform **refresh token** (prod) in secure storage on the admin's device only.

### 6.3 Schema upgrades
- Every app release bundles all migrations. On launch the app reads `schema_version`:
  - **Admin's app:** runs any pending migrations and redeploys the functions, after asking the admin to confirm.
  - **Member's app on an older schema:** runs in compatible mode or shows "Ask \<admin\> to open the app to update."
- Rule: migrations must stay backward compatible with the previous app version.

### 6.4 Paused projects
- **App:** detects a pause from **HTTP 540** ("Project paused") on any function call, plus Management API status on the admin's device. Restore takes ~3 min (measured), and the functions may return 500 for a few seconds after the project is healthy. The admin gets a **Restore** button (`POST /v1/projects/{ref}/restore`); members see "Ask \<admin\>".
- **Frame:** keeps showing cached photos and retries on its backoff.
- Daily frame syncs should prevent a pause (verify, §14).

---

## 7. Backend package (`backend/supabase/`)

The same package is deployed to the dev project (through the CLI) and to every family project (through the wizard).

### 7.1 Schema
Implemented in `backend/supabase/migrations/` (0001 tables, 0002 access, 0003 jobs). Tables in `public` are readable under RLS; secrets and server-only state live in the unexposed `private` schema.

| Table | Key columns / notes |
|---|---|
| `schema_version` | `version int pk`, `applied_at` |
| `project_members` | `user_id pk → auth.users`, `role` (`admin`/`member`; **at most one admin**, enforced by a partial unique index), `display_name`, `invited_by`, `created_at` |
| `palettes` | `id`, `name`, `colors jsonb` (`[{name, color, deviceColor}]`, same shape as `presets.json`) |
| `device_models` | `id` (e.g. `reterminal-e1002`), `name`, `width`, `height`, `palette_id`. Upserted by `seed.sql`, generated from `shared/presets.json` |
| `frames` | `id uuid`, `hw_id text unique`, `model_id`, `name`, `fw_version`, `manifest_version bigint`, `last_seen_at`, `battery_pct`, `rssi`, `sd_free_bytes`, `created_at`. No owner column: ownership is `frame_members.role = 'owner'` |
| `frame_members` | `frame_id`, `user_id → project_members` (leaving the space removes frame memberships), `role` (`owner`/`member`; **one owner per frame**, partial unique index), pk(frame_id, user_id) |
| `frame_settings` | `frame_id pk`, `image_interval_s` (14400), `display_order` (`random`/`sequential`), `sync_interval_s` (86400), `quiet_start`/`quiet_end` (nullable `time`, both or neither), `timezone` (IANA, default `UTC`), `updated_at` |
| `images` | `id uuid`, `frame_id`, `uploaded_by` (nullable, `on delete set null`: photos outlive a deleted account), `storage_path`, `sha256`, `bytes`, `width`, `height`, `position double` (set when `ready`), `status` (`pending`/`ready`), `created_at`; unique(frame_id, sha256) |
| `invites` | `id`, `frame_id` (null = project-only), `created_by`, `expires_at`, `max_uses`, `uses` |
| `quota_config` | `scope` (`frame`/`user`/`project`), `max_images`, `max_bytes` (null = unlimited). **Values TBD.** Placeholder: project `max_bytes` = 90% of 1 GiB |
| `private.frame_secrets` | `frame_id pk`, `secret_hash` (SHA-256 hex of the device secret) |
| `private.removed_frames` | `secret_hash pk`, `removed_at`. Tombstone written when a frame is deleted, so `/sync` can answer `410` (removed) instead of `401` (unknown secret) |
| `private.invite_codes` | `invite_id pk`, `code_hash` |
| `private.pairing_tokens` | `token_hash`, `user_id`, `frame_name`, `timezone`, `expires_at` (10 min), `used_at` |
| `private.config` | key/value: `maintenance_secret` (random, made by 0003), `project_url` (written by the migration runner) |
| Usage | Computed by `app-api` for `GET /usage` (sum of `images.bytes`), shown in the app against the free-tier limit. Added with the functions |

- **RLS:** members can `select` the rows they belong to. **All writes go through `app-api`** (service role), so quota checks, `manifest_version` bumps and permission rules live in one place. Clients get `SELECT` grants only; Supabase's default grants on `public` are revoked (including default privileges for future objects), so every new table or function must be granted explicitly.
- **Permissions:**
  - Photos: a member deletes their own; the frame owner deletes any.
  - Frame settings, reorder and frame invites: frame owner.
  - Project members and project-only invites: admin.

### 7.2 Storage
- Private bucket `frame-images`, path `{frame_id}/{image_id}.png`.
- Max 512 KB per object; MIME type `image/png` only.

### 7.3 `device-api` (auth: `Authorization: Bearer <device_secret>`, compared by SHA-256 hash)
- **`POST /claim`** `{pairing_token, hw_id, model_id, fw_version}` → `{frame_id, device_secret}`.
  - Creates the frame (owner = the token's user), a default settings row, and an owner `frame_members` row. The secret is 32 random bytes, returned once.
  - Returns `409` if `hw_id` is already paired in this project to a different owner.
- **`POST /sync`** `{manifest_version, fw_version, battery_pct, rssi, sd_free_bytes, local_ids[]}` →
  ```json
  { "manifest_version": 42,
    "settings": { "image_interval_s": 14400, "display_order": "random", "sync_interval_s": 86400,
                  "quiet_start": "22:00", "quiet_end": "07:00", "tz_posix": "CET-1CEST,M3.5.0,M10.5.0/3" },
    "images": [ { "id": "…", "sha256": "…", "bytes": 61234, "position": 1.0, "url": "<signed, 1h>" } ],
    "server_time": 1790000000 }
  ```
  - `images` is omitted when `manifest_version` is unchanged.
  - Signed URLs are created only for ids **not** in `local_ids`; ids already on the device appear without `url`.
  - Updates the heartbeat fields.
  - `tz_posix` is derived from IANA using a table bundled in `functions/_shared`.
  - Returns **`410 Gone`** if the frame was removed. The frame then wipes itself.

### 7.4 `app-api` (auth: Supabase JWT + `project_members`)
**Pairing and images**
- `POST /pairing-tokens` → one-time token (10 min).
- `POST /images/request-upload` `{frame_id, sha256, bytes, width, height}`.
  - Checks membership, that dimensions match the frame model, quotas, and dedupe.
  - Inserts a `pending` row and returns a signed upload URL.
- `POST /images/finalize` `{image_id}` → checks the object exists, its size, PNG signature and IHDR dimensions → `ready`, bumps `manifest_version`.
- `POST /images/delete`, `POST /images/reorder`.

**Frames**
- `PATCH /frames/{id}/settings`, `PATCH /frames/{id}` (rename).
- `DELETE /frames/{id}` → removes the images, objects and members. The frame gets 410 on its next sync.

**Invites and members**
- `POST /invites`, `POST /invites/accept` `{code, display_name}`.
- `DELETE /frames/{id}/members/{user}`, `DELETE /project-members/{user}`.

**Account and usage**
- `PATCH /me` `{display_name}`.
- `GET /usage` → frame, user and project usage + limits.
- `DELETE /me[?delete_photos=true]` → account deletion (required by the App Store). The deletion flow has an **"Also delete my photos" checkbox** (sets `delete_photos`); unchecked, the photos stay with `uploaded_by` → null. For the admin, the app also offers "delete the whole family space" through the Management API.

### 7.5 Scheduled jobs (pg_cron)
- **Hourly, SQL** (`private.hourly_cleanup`): expired or used pairing tokens, expired or used-up invites, and auth users older than 24 h with no membership (people who signed in but never joined, and people who left).
- **Hourly, SQL** also drops `pending` image rows older than 24 h (0004).
- **Hourly, via `pg_net`** (`private.request_maintenance` → `POST app-api/internal/maintenance` with `x-maintenance-secret`): delete `frame-images` objects older than 1 h that no `images` row points to (stale uploads, and objects left behind when a delete failed after its row was gone). Storage objects can't be deleted with SQL on Supabase (`protect_objects_delete` trigger), hence the function call.
- No daily usage refresh: usage is computed on request.

### 7.6 API contract
`shared/api/openapi.yaml` is the contract for both functions. It is written first in Phase 1B, and the functions, `frame_sim`, the Dart client and the firmware all follow it.

---

## 8. Flutter app (`app/`)

> **The screens, navigation, flows, layouts and visual design are decided in Phase 2** and recorded in `docs/app-flow.md`. This section fixes only the technical base that Phase 2 builds on.

### 8.1 Platforms and the "desktop is fully functional" requirement
| Capability | iOS / Android | Desktop (Windows required; macOS/Linux nice-to-have) |
|---|---|---|
| Sign-in | native Google/Apple (§5.3) | loopback PKCE Google; Apple TBD in Phase 2 (§5.3) |
| Supabase platform connect | OAuth + PKCE, custom-scheme redirect | OAuth + PKCE, loopback redirect; **PAT paste in dev mode** |
| Photo input | `image_picker` (multi-select) | `file_selector` + drag-and-drop |
| Decode/resize | `dart:ui` `instantiateImageCodec` (HEIC on iOS) | same (no HEIC on Windows; JPEG/PNG/WebP) |
| Secure storage | `flutter_secure_storage` | same (Windows Credential Manager / macOS Keychain) |
| Invites | QR scan (`mobile_scanner`) + deep link (`app_links`) | paste link/code; `app_links` custom scheme (registered on Windows) |
| BLE pairing | `universal_ble` (supports Android/iOS/macOS/Windows/Linux; **verify Windows pairing with passkey**, §14) | same, or the **frame_sim pairing path** (enter pairing token manually) |
| Frame testing without hardware | – | **`tools/frame_sim`** + a dev-only "simulated frame" view in the app |

### 8.2 Tech base (kept small)
- **Packages:** `supabase_flutter`, `google_sign_in`, `sign_in_with_apple`, `universal_ble`, `image_picker`, `file_selector`, `desktop_drop`, `go_router`, `flutter_riverpod`, `crypto`, `flutter_secure_storage`, `cached_network_image`, `app_links`, `mobile_scanner`, `url_launcher`.
  - Final choices can be revisited in Phase 2 if the UI needs change them.
- **Layers:**
  - `lib/data/` (repository interfaces + Supabase implementations)
  - `lib/provisioning/` (Management API client behind a `PlatformTokenProvider` that accepts PAT or OAuth; bundled migrations and functions in `assets/backend/`)
  - `lib/imaging/` (pure Dart, no Flutter imports, so it can be unit-tested and reused by `frame_sim`)
  - `lib/ble/`
  - `lib/features/…` (defined in Phase 2)
- **Dev mode** (a compile-time flag or hidden toggle):
  - PAT entry
  - point at the dev project
  - a simulated-frame panel
  - verbose logs

### 8.3 Imaging pipeline (`lib/imaging/`, runs in `Isolate.run`) — fully specified
1. **Crop:** aspect-locked to the target model's `width/height`. When no crop is set, **center-crop** as in `getCroppedCanvas()` in `reference/ink-frame-lab/js/export.js`.
2. **Resize** to the model resolution (high-quality filter).
3. **Dither:** a direct port of `reference/ink-frame-lab/js/dithering.js`:
   - `nearestPaletteColor` (squared RGB distance, first minimum wins)
   - error diffusion with all 9 `ED_KERNELS` + serpentine, using **`Float32List`** to match the JS `Float32Array` rounding
   - ordered (Bayer, power-of-two matrix, threshold formula unchanged)
   - random (`luma`/`rgb`, strength 40) with an injectable RNG for tests
   - plain quantization
   - **Output is a `Uint8List` of palette indices** (not RGBA). `replaceColors()` becomes the PNG palette, mapping index → `deviceColor`.
4. **Preview:** indices → calibrated `color` values, so the user sees what the panel will display. The 3D viewer from ink-frame-lab is **not** ported.
5. **Indexed PNG encoder** (custom, small):
   - IHDR colour type 3; bit depth **4** (2 for ≤4 colours, 1 for 2 colours)
   - `PLTE` = palette `deviceColor`s; no tRNS
   - `IDAT` via `ZLibCodec(level: 9)` (`package:archive` on web if ever needed)
   - try filter strategies (all-none, all-sub, all-up, per-row minimum) and keep the smallest
   - `IEND`
   
   Expected ~40–120 KB per 800×480 image, versus ~200–400 KB for today's 24-bit PNGs.
6. **sha256** of the PNG bytes → `request-upload` → PUT to the signed URL → `finalize`.

Dithering options follow ink-frame-lab (algorithm, kernel, serpentine, Bayer size, random type), with a default preset per model.

### 8.4 Golden parity tests
- `tools/golden/` (Node): loads `reference/ink-frame-lab/js/dithering.js` with an `ImageData` polyfill. Runs every mode and kernel on fixed **pre-resized RGBA** inputs. Writes index arrays to `shared/test-vectors/`.
  - Inputs are pre-resized so resize differences don't count.
- **Dart tests** must match those **exactly** for quantization, ordered, and every ED kernel (serpentine on and off). Random mode is checked statistically.
- **Encoder tests:** the output decodes back to identical indices (decode with `package:image` in tests only), is a valid PNG, and its size is logged.

### 8.5 Questions Phase 2 must answer (input for the planning session)
- The first-run experience: set up a new space vs join by invite; how the wizard's progress and failure states look.
- Navigation model: spaces → frames → photos; tabs vs drill-down; desktop layout (multi-pane?) vs mobile.
- The add-photos flow: batch picking, per-photo crop, dithering adjustments (how much control?), preview, upload queue and retry.
- How the frame screens show status (last sync, battery, "changes arrive at next sync / press green").
- Usage display (project storage vs free-tier limit, per-frame and per-user), warnings, and what happens at the limit.
- Invite UX: QR, share sheet, desktop paste; member management; roles shown.
- Settings UX: intervals, order, quiet hours, timezone.
- Add-frame (BLE) flow and its error states: Bluetooth off, wrong passkey, wrong Wi-Fi password, claim failed.
- Admin tools: schema upgrade prompt, paused-project restore, delete space.
- Apple sign-in on Windows (§5.3); visual design (theme, typography, light/dark); accessibility; localization (v1 English only?).

---

## 9. Firmware (`firmware/`, Phase 4)

### 9.1 Project
- **`platformio.ini`:** env `reterminal_e1002`, board `seeed_xiao_esp32s3`, OPI PSRAM, custom `partitions_ota.csv` (nvs, otadata, **app0/app1 ~6 MB each**, coredump; the chip has 32 MB flash).
  - Pinned `lib_deps`: GxEPD2 (git tag; GitHub version, as the current install notes require), PNGdec, Adafruit GFX, NimBLE-Arduino, ArduinoJson.
- **Build flags:** `FW_VERSION`, `MODEL_ID`, `FIRMWARE_FEED_URL`, `FW_SIGNING_PUBKEY`. There is **no** backend URL in the firmware; it arrives over BLE.
- **Layout:**
  - `src/main.cpp` (boot state machine)
  - `src/board/e1002.h` (pins; one header per future model)
  - `src/display/` (render + screens: pairing, ready, error, removed)
  - `src/storage/sd_cache.*`
  - `src/net/{wifi,api_client,sync,ota}.*`
  - `src/ble/provisioning.*`
  - `src/config/nvs_settings.*`
  - `src/power/{battery,sleep,schedule}.*`

### 9.2 Kept from `reference/ink-frame-lab/firmware/reTerminal_E1002_DigitalFrame.ino`
Moved into modules with the logic unchanged unless noted:
- Pin defines.
- `initSPI`, `initSD`/`deinitSD` (with power-cycle retry).
- PNG callbacks and `decodePNGToBuffer` into the PSRAM `frameBuffer`.
- `drawBufferToDisplay`, `drawBatteryBar`, `getBatteryPercent`.
- The wake setup in `enterDeepSleep`: ext0 green, ext1 white buttons.
- `getWakeAction` and `pickNextImage`, which now index the manifest list instead of `1..N`.
- The screen style of `displayError`/`displayNoPhotos`.

**Removed:** WebServer, soft-AP, `WEBPAGE_HTML`, the upload/delete/list/settings handlers, `config.txt`, `countImagesOnSD`.

### 9.3 Persistent state
- **NVS:** Wi-Fi SSID and password, `api_base_url`, `device_secret`, `frame_id`, settings, `tz_posix`, last successful sync time.
- **SD:** `/cache/{image_id}.png` + `/cache/manifest.txt` (`id sha256 bytes position` per line; always written to a tmp file and then renamed).
- **RTC memory:** `lastImageIndex`, `sequentialIndex`, `syncBackoffLevel`. System time survives deep sleep, and NTP corrects it at every sync.

### 9.4 Boot state machine
```
boot/wake
 ├─ missing Wi-Fi details / api_base_url / device_secret ─► PAIRING
 ├─ green held ≥3 s at boot ─► PAIRING (re-provision; keep cache until the new claim succeeds)
 ├─ green held ≥10 s ─► FACTORY RESET (clear NVS + /cache) ─► PAIRING
 ├─ wake = green short press ─► SYNC (forced) ─► SHOW
 ├─ timer wake & sync due (or backoff retry due) ─► SYNC ─► SHOW
 └─ otherwise ─► SHOW
SHOW: in quiet hours → sleep until quiet_end without refreshing
      else next image from manifest (white L/R = prev/next in sequential; next in random)
      → decode → display → sleep min(image_interval, until quiet_start, until next sync)
```
- **SYNC:** Wi-Fi (15 s timeout) → NTP → `POST {api_base_url}/device-api/sync` through `WiFiClientSecure` + the built-in CA bundle (**never** `setInsecure`).
  1. Download missing images to `/cache/tmp` and check sha256 → rename.
  2. Delete files not in the manifest → write the manifest → save settings to NVS.
  3. OTA check (§10).
  4. Wi-Fi off.
- **Failure:** keep showing cached photos. Backoff 1 h → 2 h → 4 h…, capped at `sync_interval`. A small red marker shows in the battery-bar strip until the next success. A paused project is treated like any server error.
- **After a forced sync:** if new images arrived, show the newest first. The status LED blinks during the sync (no e-paper "syncing" screen, which would cost a ~20 s refresh).
- **`410`:** wipe the cache and secret → screen "This frame was removed. Hold the green button for 3 s to set it up again."
- **Empty manifest:** "Ready. Add photos in the Ink Frame app."

### 9.5 BLE pairing (NimBLE custom GATT + LE Secure Connections)
1. Entering PAIRING creates a random 6-digit **static passkey** and shows it on e-paper with the name `InkFrame-XXXX` and short instructions. It advertises for 10 min, then sleeps.
2. Characteristics:
   - `info` (read: hw_id, model_id, fw_version)
   - `wifi_scan` (notify: SSIDs + RSSI)
   - `provision` (write, chunked JSON: `ssid`, `password`, `api_base_url`, `pairing_token`)
   - `status` (notify: `wifi_connecting|wifi_failed|claiming|claimed|error:<code>`)
3. The link is encrypted by OS pairing with the passkey shown on screen, so the password and token are never sent in plaintext.
4. Join Wi-Fi → `POST /claim` → store the secret → notify `claimed` → first sync → ready screen.

---

## 10. OTA and the central firmware feed (Phase 4)

- **Feed:** `FIRMWARE_FEED_URL/{model_id}/manifest.json` (GitHub Pages) with `{version, url, size, sha256, min_battery_pct, rollout_percent, signature}`. `url` is a GitHub Release asset.
- **Signing:** Ed25519 (or ECDSA P-256) over the manifest, with the **public key compiled into the firmware**. This is essential, because the feed is shared by every frame.
- **Install conditions:** the version is newer, `hash(hw_id) % 100 < rollout_percent`, and battery ≥ `min_battery_pct`.
- **Install steps:** stream into `Update` → check sha256 → set the boot partition → reboot → after the new image completes a successful boot and sync, mark it valid.
  - Rollback: see §14. If the bootloader can't roll back, add a boot-count fallback.
- **CI:** tag `fw-v*` → `pio run` → sign → create the release asset → publish `manifest.json`. None of this uses family Supabase egress.

---

## 11. Phases in detail

### Phase 0 — Repo scaffold (Claude)
- Create the directory layout (§4), `.gitignore`, `CLAUDE.md`, a README overview, `docs/` stubs, and copy `reference/ink-frame-lab/presets.json` → `shared/presets.json`.
- **Exit:** structure committed; `reference/` untouched.

### Phase 1 — Supabase account and token (User) ✅ gate
The user:
1. Creates a Supabase account (and an org if prompted).
2. Creates a **Personal Access Token**: Dashboard → Account → Access Tokens.
3. Makes it available to the session as the environment variable `SUPABASE_ACCESS_TOKEN`, or in `backend/.env.local` (gitignored). **Never paste it into committed files.**
4. Decides which **region** to use for the dev project.
5. *(Can wait until Phase 3)* Google Cloud OAuth client IDs (iOS, Android, Web, Desktop) and the Apple App ID with Sign in with Apple.

Notes:
- The free plan allows 2 active projects: **dev** (backend work) plus one spare for testing the wizard.
- A cloud session needs the token set as a session secret or environment variable.

### Phase 1B — Backend (Claude)
1. `shared/api/openapi.yaml` (contract first).
2. Migrations (§7.1–7.2, 7.5) + `seed.sql` generated from `shared/presets.json`.
3. `device-api` and `app-api` (§7.3–7.4) + shared helpers.
4. Tests: Deno integration tests through the real APIs (PostgREST, Storage, Edge Functions) with real user sessions, against the dev project (`backend/supabase/tests/`).
5. Link the **dev project** (already created by the user: ref `vrhsxzedzhvujnirsuhg`, region `ap-south-1`) with the PAT (CLI `supabase link`, `db push`, `functions deploy`), or through the Management API.
6. **Spikes**, results in `docs/spikes/`:
   - (a) Management API coverage with the PAT: create project, SQL query, function deploy, auth config, restore, usage/egress endpoints. The dev token has org access (org `psmyles`, `xzkqkhlbnexqldkhuohf`), so create-project and restore can be tested in the spare free slot.
   - (b) Auth config: can Google be enabled with client IDs only (no secret) for ID-token sign-in? Apple with the bundle ID only?
   - (c) Supabase OAuth App + PKCE without a client secret.
7. `tools/frame_sim` (Dart CLI): `claim --token`, `sync` (keeps a local cache dir mirrored), `status`, `render` (writes the current image + a manifest summary). Also `tools/dev` scripts: upload test PNGs as a user, reset the dev project, and bundle the backend for the app.
- **Exit:** the curl/`frame_sim` scenario in §12.1 passes against the dev project; spike findings are recorded; §14 is updated.

### Phase 2 — Flutter app flow and UI planning session (User + Claude) ✅ gate
- A dedicated planning session, with **no app code**. Inputs: §8 and the Phase 1B spike results. Works through §8.5.
- **Output:** `docs/app-flow.md`, containing:
  - screen inventory, navigation map, per-screen states (loading/empty/error)
  - mobile vs desktop layouts, component list, visual design direction
  - final package list
  - a Phase 3 milestone breakdown
- **Exit:** the user approves `docs/app-flow.md`.

### Phase 3 — Flutter app (Claude)
Milestones will be refined in Phase 2. Baseline:
- **3a** Scaffold (all platforms incl. Windows), config, dev mode, data layer, Supabase connection to the dev project, sign-in (Google on mobile + desktop loopback; Apple on iOS/macOS).
- **3b** `lib/imaging/` port + indexed PNG encoder + golden tests (§8.3–8.4).
- **3c** Core screens per `docs/app-flow.md`: spaces, frames, photos (add/crop/preview/upload/delete/reorder), settings, usage.
- **3d** Invites and members; display names.
- **3e** Provisioning wizard (PAT in dev → OAuth in prod), schema upgrade, restore, delete space.
- **3f** BLE add-frame flow (app side). Before hardware exists, the dev-mode "pair with token" path and `frame_sim` stand in for the frame.
- **Exit:** the §12.2 scenarios pass on Windows desktop and on at least one phone.

### Phase 4 — Firmware (Claude + User with hardware)
- **4a** PlatformIO port (§9.1–9.2), SD cache, sync + mirror, settings, quiet hours. Temporary serial provisioning (Wi-Fi/URL/secret over UART).
- **4b** BLE pairing (§9.5) end to end with the app; remove serial provisioning.
- **4c** OTA + signed central feed + release CI (§10).
- **Exit:** the §12.3 matrix passes on a real E1002.

### Phase 5 — Hardening and release
- Privacy policy, App Store / Play listings, TestFlight / internal testing, account and space deletion checks, battery measurements, docs for families.

---

## 12. Verification

### 12.1 Backend (Phase 1B)
Implemented in `backend/supabase/tests/backend_test.ts` (23 steps, all passing 2026-09-25). The suite creates its own admin, so it **skips when the target project already has one**: once the developer is the dev project's admin (Phase 3), run it against the spare project.
- RLS tests:
  - a non-member can't read anything
  - an auth user without membership is blocked
  - a member can't delete others' photos
  - the owner can
  - quota rejections
- Scenario (script + `frame_sim`):
  1. create a pairing token → `claim` → `sync` (empty)
  2. upload 3 → `sync` downloads 3
  3. delete 1 → `sync` mirrors (2 left)
  4. reorder → the positions change
  5. settings change → reflected
  6. unchanged `manifest_version` → `images` omitted
  7. delete the frame → `410`

### 12.2 App (Phase 3)
- Golden parity (§8.4) passes in CI.
- **On Windows desktop:**
  1. dev PAT → the wizard creates a fresh space in the spare project slot
  2. sign in with Google (loopback)
  3. drag in 5 photos → crop/preview → upload
  4. `frame_sim sync` receives them
  5. delete one → `frame_sim` mirrors
- **On a phone:** join through the invite QR → Apple (iOS) or Google sign-in → type a display name → upload → `frame_sim` receives it with the right uploader.
- The usage view matches the `project_usage` numbers.

### 12.3 Firmware (Phase 4) on a real E1002
- **Pairing:** wrong Wi-Fi password; wrong passkey.
- **Sync:** add, delete and reorder → forced sync (green press); settings change; quiet hours across midnight.
- **Failures:** Wi-Fi down / server 500 / paused project (backoff; cached photos still shown); `410` wipe; power cut mid-download (tmp file never shown); SD full.
- **OTA:** success; bad hash; bad signature; rollback.
- **Decoding:** 4-bit palette PNGs from the app decode correctly.
- **Battery:** measure sync duration and current with a USB power meter and estimate battery life.

### 12.4 End to end
Fresh admin → wizard → add frame over BLE → upload → press green → the photo appears. A second user joins through an invite → uploads → the frame shows it at its next sync. Leave the project with only daily frame syncs for more than 7 days and confirm it isn't paused.

---

## 13. Progress checklist
- [x] Phase 0 — scaffold
- [x] Phase 1 — Supabase account + PAT available to sessions (user). Dev project `ink-frame` (ref `vrhsxzedzhvujnirsuhg`, `ap-south-1`); token in `backend/.env.local`. Google/Apple client IDs still pending (can wait until Phase 3)
- [ ] Phase 1B — contract ✅ · migrations ✅ · device-api ✅ · app-api ✅ · tests ✅ · dev project deployed ✅ · spikes (a) ✅ (b) config ✅ (c) · frame_sim · dev tools
- [ ] Phase 2 — `docs/app-flow.md` approved
- [ ] Phase 3 — 3a · 3b · 3c · 3d · 3e · 3f
- [ ] Phase 4 — 4a · 4b · 4c
- [ ] Phase 5 — release

---

## 14. Verify list (assumptions not yet confirmed; check before relying on them)
- Supabase free-tier limits today (storage, egress, DB size, Edge Function calls, MAU), the **2 active free projects** rule, and whether daily Edge Function + DB traffic from a frame counts as activity against the **7-day inactivity pause**.
- ✅ ~~Management API coverage~~: all confirmed with a PAT, see `docs/spikes/a-management-api.md`. **Exception:** no storage-size or egress endpoint (only hourly request counts), so the app shows storage from the database and can't show egress. **2 active free projects** rule confirmed (400, message quoted in the spike doc).
- Supabase OAuth App: scopes, and whether **PKCE works without a client secret**. If not, add a small token-exchange function in `central/`.
- Google provider: native ID-token sign-in **without a client secret**, and several client IDs (iOS, Android, Web, Desktop) allowed at once. Apple provider: bundle ID only for native. **Config part ✅** (accepted with no secret; IDs stored as one comma-separated list, `docs/spikes/b-auth-config.md`). Actual sign-in still to verify with real client IDs in Phase 3a.
- Mobile OAuth redirect via an HTTPS bounce page on GitHub Pages (§6.1): the Supabase OAuth App accepts it as a callback URL, and the system browser hands `inkframe://` back to the app on iOS and Android.
- Windows desktop: the Google loopback PKCE flow, and whether `universal_ble` can do LESC passkey pairing on Windows (and macOS).
- ✅ ~~Whether the Edge Functions gateway needs the anon key as `apikey` for device calls.~~ **No**, with `verify_jwt = false` (2026-09-25), so frames don't store `anon_key`.
- ESP32 newlib: parses POSIX TZ strings with angle-bracket names (e.g. `<+1030>-10:30<+11>-11,M10.1.0,M4.1.0`), as produced by `_shared/tz.ts`.
- PNGdec: 4-bit indexed PNG through `getLineAsRGB565`.
- Arduino-ESP32: bootloader app rollback support.
- E1002: status-LED GPIO; whether there is an external RTC (use it for quiet hours if present).

## 15. Open decisions (defaults used until changed)
- **Re-claiming a frame paired in another family's project:** default is that a **factory reset (hold 10 s)** frees the frame locally. The old project's frame row goes stale, and the old owner can delete it in the app.
- **Who changes frame settings:** default is the frame owner only.
- **Order of photos from several members in sequential mode:** default is upload time; the owner can reorder.
- **Quota starting values:** `quota_config`, to be decided (placeholder: project ≈ 90% of the free storage limit; no per-frame/per-user limit).
- **Apple sign-in on Windows/Linux:** decided in Phase 2.
- **Set by the API contract** (`shared/api/openapi.yaml`), confirmed by the user 2026-09-25:
  - ✅ A member who leaves or is removed from a frame: **their photos stay** on it; the owner can delete them.
  - ✅ **One admin per space**, at most. There is no role-change endpoint.
  - ✅ Deleting an account (`DELETE /me`), or the admin removing someone from the space: **only the account and memberships are deleted; their photos stay** (`uploaded_by` → null), unless the user ticks **"Also delete my photos"** when deleting their own account. Frames a **member** owns **pass to the admin** and keep running (if the space has no admin, they are deleted). Only when the **admin** deletes their account are their frames (and every photo on them) deleted (`410`).
  - ✅ The admin can delete their account **at any time**, even with other members in the space, after a clear warning of the consequences: their frames are removed, and the space is left with no admin, so nobody can create project invites, remove members, upgrade the schema or restore a pause.
  - ✅ Reorder moves **one image at a time** ("place after X"), not a whole-list replace, so it can't conflict with uploads in progress.
  - ✅ Settings ranges: image interval **1 h–2 days**, default **4 h**; sync interval **1 h–2 days**, default **24 h**.
  - ✅ Invites: single use and 7 days by default; at most 50 uses and 30 days. Codes are 10 Crockford base32 characters (`XXXXX-XXXXX`).
  - ✅ Re-claiming by the **same** owner (green held 3 s) keeps the frame, its photos and settings, and issues a new secret.

## 16. Decision log
- 2026-09-25: Spikes (a) and (b). A throwaway project created entirely through the Management API (`tools/dev/provision.ts`: create → healthy in ~4 s → migrations → multipart function deploy → auth config, 17 s total) passed all 23 backend tests, then was paused (~67 s; functions answer HTTP 540), restored (~2 min 47 s; data, schema and cron intact) and deleted. Google/Apple providers accept client IDs with no secret. The wizard deploys function **source** through the multipart endpoint (server-side bundling), so no eszip bundling step is needed. The OAuth App form only allows HTTPS or localhost callbacks, so mobile uses an HTTPS bounce page to `inkframe://` (§6.1). Details in `docs/spikes/`.
- 2026-09-25: Backend tests are Deno integration tests through the real APIs instead of pgTAP: they sign in as real users (email/password test users on the dev project, `@test.invalid`, created and deleted by the run), so grants, RLS, storage policies and both functions are covered together, which pgTAP inside the database can't do for Storage or the functions. 23 steps cover the §12.1 scenario, RLS, every permission rule and most error codes. They found one bug: owner-only actions answered `not_frame_member` instead of `not_frame_owner` to project members who aren't on the frame (fixed in migration 0005).
- 2026-09-25: `device-api` and `app-api` written (Hono + zod, `functions/_shared`) and deployed to the dev project with `supabase functions deploy --use-api` (server-side bundling, no Docker). Both run with `verify_jwt = false` (`backend/supabase/config.toml`); `app-api` verifies the user JWT itself with `auth.getUser`. Writes go through `svc_*` SQL functions (migration 0004), one transaction each, callable only by `service_role`; errors carry the contract's codes. **§14 resolved:** the Functions gateway doesn't need an `apikey` header when `verify_jwt` is off, so `anon_key` is dropped from the frame's NVS and BLE payload. `tz_posix` comes from `_shared/tz.ts`, generated from the system tzdata (2026c, 597 zones incl. aliases) by `tools/dev/gen-tz.ts`. The maintenance endpoint became an orphan-object sweep; stale pending rows are dropped by SQL. npm versions are pinned to releases at least a day old because Deno's default minimum dependency age (24 h) refuses newer ones.
- 2026-09-25: Migrations 0001–0003 written and applied to the dev project through the Management API (`tools/dev/migrate.ts`, the same path as the wizard). Schema changes from the original §7.1: secrets moved to an unexposed `private` schema (`frame_secrets`, `invite_codes`, `pairing_tokens`, `removed_frames`, `config`); `frames.owner_id` dropped in favour of `frame_members.role = 'owner'` (one source of truth); `last_sync_status` dropped (only successful syncs reach the server; `last_seen_at` covers it); usage views replaced by on-request computation in `app-api`. `seed.sql` is an idempotent upsert generated from `shared/presets.json` and applied after migrations on every run; `reTerminal E1002 7.3` maps to `reterminal-e1002`, other preset ids are slugged. Facts found on the dev project: `pg_cron` 1.6.4, `pg_net` 0.20.4 and `pgtap` 1.3.3 are available; the query endpoint runs as `postgres` and accepts multi-statement transactions; `storage.objects` has a `protect_objects_delete` trigger, so objects are deleted only through the Storage API (added `POST /app-api/internal/maintenance` to the contract). Contract also gained an optional `timezone` on `POST /pairing-tokens`.
- 2026-09-25: Considered and **rejected** handing the admin role to another member on account deletion. The family's Supabase project lives in the admin's Supabase account, so the admin role can't meaningfully move with it. An admin leaving means the space is left without an admin, as set out in §15.
- 2026-09-25: At most one admin per space (partial unique index). `DELETE /me` gains `delete_photos` for an "Also delete my photos" checkbox. Defaults: image interval 4 h, sync interval 24 h (sync reverted from 4 h). If a member deletes their account while the space has no admin, their frames are deleted.
- 2026-09-25: Further user changes: (1) deleting an account, or an admin removing a member, deletes only the account and memberships; photos stay, so `images.uploaded_by` is nullable; (2) the admin may delete their account at any time after a warning (`sole_admin` 409 removed); the space can then be left with no admin; (3) image and sync intervals both default to 4 h (was 1 h / 24 h).
- 2026-09-25: User confirmed the §15 contract defaults with two changes: (1) a member's frames are **not** deleted when they leave the space or delete their account; ownership passes to the admin, and only the admin's own account deletion deletes frames; (2) image and sync intervals both range 1 h–2 days. A 2-day sync cap also keeps every family project well inside the 7-day inactivity window.
- 2026-09-25: API contract written (`shared/api/openapi.yaml`, OpenAPI 3.1, lints clean). Added the `removed_frames` tombstone table (§7.1). The project has both a legacy anon key and a `sb_publishable_` key, so the contract calls it the "public key" and accepts either. Behaviour defaults the plan left open are listed in §15.
- 2026-09-25: The user replaced the token with one that has full access to org `psmyles` (`xzkqkhlbnexqldkhuohf`). Organization endpoints, org members, project keys, auth config, functions and SQL all return 200/201. The project-scoped limitation in the next entry no longer applies.
- 2026-09-25: Phase 1. The user created the dev project `ink-frame` (ref `vrhsxzedzhvujnirsuhg`, region `ap-south-1`) and a token stored in `backend/.env.local` as `SUPABASE_ACCESS_TOKEN`. The token is scoped to that project: SQL, API keys, auth config and functions work (200), but `GET /v1/organizations` returns `[]` and the org endpoint returns 403. Enough for backend work; spike (a) create-project/restore and the §12.2 wizard test need an account-wide token.
- 2026-09-25: Initial plan. One Supabase project per family (was: a shared central project). Google/Apple kept over anonymous auth, for recovery. Display names typed at join. Desktop must be fully functional. Build order: Supabase account/token → backend → Flutter planning session → Flutter → firmware.
