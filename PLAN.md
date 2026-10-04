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
- A **native Flutter companion app** (iOS, Android, and fully functional on **desktop** for easy testing). It crops, dithers and compresses photos **on the device** and uploads them to **the frame's own Supabase project** (free tier), in its owner's Supabase account.
- **Frames** sync daily (or when the green button is pressed). They mirror their cloud photos onto the SD card, which acts only as a cache, and show them offline as today.
- An **in-app wizard** that sets up each frame's Supabase project automatically. The person who sets up a frame (its **owner**) needs a free Supabase account; everyone needs only a Google/Apple login.

---

## 2. Decisions made

| Topic | Decision |
|---|---|
| Audience | Consumer product for other people |
| Backend tenancy | **One Supabase project per frame**, in the owner's free Supabase account. Photos are processed for one panel's resolution and palette, so a project never mixes panel types. A free account runs up to **2 frames** (2 active free projects); a third frame is set up by someone else with their own account |
| Project setup (production) | **In-app wizard** via Supabase OAuth + Management API. It creates the project, schema, buckets, functions and auth config |
| Project setup (development) | Developer **Personal Access Token (PAT)** with the Supabase CLI and Management API. The wizard's API client accepts a PAT or an OAuth token through one interface |
| Login | **Sign in with Google + Sign in with Apple** through native ID-token sign-in, using the developer's OAuth client IDs. Families never touch OAuth consoles (§5). Anonymous sign-in was considered and **rejected**: social login lets members recover access on a new device just by signing in again |
| Finding your frames on a new device | A small developer-run **directory** (Cloudflare Worker + D1, free plan): for each Google/Apple account (hashed), the addresses of its frames. Signing in is enough; no link or other device needed. Photos and everything else stay in the families' projects (§3) |
| Display names | Typed by the user when joining a frame (not taken from the Google/Apple profile; reused as the default for the next frame), and editable later |
| Users within a project | One **owner** (set up the frame; hosts the project) and any number of **members**. The app lists every frame a person belongs to, across projects |
| Sharing | The owner invites people. Members delete their own photos; the owner can delete anything |
| App | Native Flutter, **no webview**. Dithering ported to Dart; output PNG compressed (indexed palette) |
| App platforms | **iOS + Android** (store targets) + **desktop** (Windows required as the developer's machine; macOS/Linux nice-to-have), with desktop fully functional for testing |
| Frame onboarding | **BLE** from the app: Wi-Fi details + the frame's API URL + pairing token. The panel model is chosen at setup; the hardware must match it |
| Hardware replacement | New hardware of the **same model** takes over the frame and keeps its photos (the old device gets `410`). A **different model** is refused until the owner switches the frame's model, which clears its photos |
| User-facing words | **album** for the photos, the people and their storage (one per frame; what has the name), **frame** only for the hardware (screen, buttons, battery, Wi-Fi, memory card), **owner** ("set up by"), **people** / "shared with", **invite someone to add photos**, "**checks for new photos**", "**connect the frame**", "**asleep because it wasn't used for a while**". Never: space, project, admin, sync, manifest, pair/claim, hardware, and "device" for the frame (it means the phone or computer). "Supabase account" appears only in setup. In code, `frame` still names the project-level thing (the `frame` table, `Frame`, the API) |
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
                ┌──────────────── developer-run (central, tiny) ────────────────────────────┐
                │  • Firmware feed: GitHub Releases assets + signed manifest.json (Pages)    │
                │  • /join and /oauth pages (Pages, static)                                  │
                │  • Directory (Cloudflare Worker + D1): hashed account → frame addresses    │
                │  • (only if required, see §14) Supabase-OAuth token-exchange endpoint      │
                └────────────────────────────────────────────────────────────────────────────┘

 Owner's app ──Supabase OAuth (prod) / PAT (dev)──► Supabase Management API ──creates/configures──┐
                                                                                                   ▼
 Flutter app ──Google/Apple ID token──►  ONE SUPABASE PROJECT PER FRAME (free tier)
   pick → crop → dither → indexed PNG     • Auth: Google/Apple providers using our client IDs
   ├──► app-api Edge Function ──────────► • Postgres: the frame, members, images, quotas
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
    api/directory.yaml        the directory's contract
    pairing.json              Bluetooth pairing UUIDs and limits (docs/pairing.md)
    test-vectors/             golden dithering inputs/outputs generated from the JS reference
  backend/supabase/
    config.toml
    migrations/               numbered SQL migrations (also bundled into the app for the wizard)
    functions/device-api/     Deno/TypeScript Edge Function
    functions/app-api/        Deno/TypeScript Edge Function (Hono router)
    functions/_shared/        shared TS (auth helpers, tz table, errors)
    seed.sql                  generated from shared/presets.json
    tests/                    Deno integration tests (RLS, functions, §12.1 scenario) against a dev project
  app/                        Flutter app (android/ ios/ windows/ macos/ [linux/]); assets/backend/ = the backend the wizard installs (tools/dev/bundle-backend.ts)
  firmware/                   PlatformIO project
  tools/
    golden/                   Node script: runs reference dithering.js → shared/test-vectors
    frame_sim/                Dart CLI frame simulator (claim/sync/mirror/render)
    ble_frame/                pretend frame over real Bluetooth (Flutter, macOS/Android; uses frame_sim)
    dev/                      dev scripts (upload test PNGs, reset dev project, bundle backend)
  central/                    GitHub Pages site: /join and /oauth pages; firmware feed (Phase 4); directory/ (Cloudflare Worker); (+ OAuth token-exchange fn if needed)
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
1. **Supabase platform token.** This is the owner's supabase.com account token: an OAuth token in production, a PAT in development. It controls the whole Supabase account: it can create or delete projects, run any SQL, and read keys.
   - Lives **only** on the owner's device, in secure storage (one token covers both of the owner's frames).
   - Used only for provisioning, schema upgrades, restoring a paused project, and reading usage.
   - **Never** used as a member identity or sent to the frame.
2. **Project user token (JWT).** Issued by the frame's project's Supabase Auth after Google/Apple sign-in. Every app user has one **per frame** they belong to. RLS and `app-api` authorize with it.

### 5.2 Native ID-token sign-in
1. The platform sheet (`google_sign_in` / `sign_in_with_apple`) returns an **ID token**. Its `aud` is *our* Google client ID or iOS bundle ID.
2. `supabase.auth.signInWithIdToken(provider, idToken, nonce)` runs against the **frame's** project. Joining a second frame reuses the same Google/Apple sign-in.
3. Supabase checks the token's signature against Google's/Apple's public keys, and checks that `aud` is in the provider's allowed client IDs.
4. The wizard writes those client IDs into each frame's project through the Management API. Client IDs are not secrets (they ship inside the app).

### 5.3 Platform matrix
| Platform | Google | Apple |
|---|---|---|
| iOS | native (`google_sign_in`) | native (`sign_in_with_apple`), required by App Store rule 4.8 because Google is offered |
| Android | native (`google_sign_in`) | **not in v1** (the web flow needs a Services ID + a secret key that expires every 6 months) |
| macOS | `google_sign_in` (supported) | native `sign_in_with_apple` (supported) |
| **Windows / Linux** | **loopback OAuth + PKCE** with a Google "Desktop app" client ID: open the system browser, catch the redirect on `http://127.0.0.1:<port>`, exchange the code, take the `id_token`, then `signInWithIdToken`. Add the Desktop client ID to the allowed client IDs | not available natively. **Decide in Phase 2** (options: none on Windows; Apple web flow; dev-only email/password on dev projects) |

### 5.4 Membership gate
- Sign-in is open at the auth layer: anyone holding a project URL + anon key could create an auth user. **Everything** is therefore gated by a `members` row, which RLS and `app-api` both check.
- The owner's row is created by the wizard; everyone else's by accepting an invite.
- A pg_cron job deletes auth users that have no membership after 24 h.

### 5.5 Joining a frame
- **Invite link:** `https://psmyles.github.io/ink-frame/join#u=<project_url>&k=<publishable_key>&c=<invite_code>`, shared as a QR code or link. The page (`central/site/join/`) opens `inkframe://join?…` on phones; on desktop the link is pasted into the app. "Use on another device" links repeat `u`/`k` once per frame and have no `c`. The fragment never reaches the server.
- **Join flow:** the app saves the project → the user signs in with Google/Apple → types a **display name** (pre-filled from their other frames) → `POST /invites/accept {code, display_name}`.
- The app keeps a **list of frames** (URL + anon key + session per frame) and shows them together.
- **New device:** the same Google/Apple ID token also signs in to the **directory** (`shared/api/directory.yaml`), which returns the account's frame addresses and a device token for later changes (app-flow §1.4). The directory verifies the token against Google's/Apple's keys and our client IDs, like Supabase does.

---

## 6. Frame project provisioning

### 6.1 Developer one-time setup
- **Supabase:** register an **OAuth App** in the developer's Supabase org (dashboard only; no API) → client id and secret. The secret is required for the token exchange (spike c), so it lives only in the Cloudflare Worker (`central/directory/`, a Worker secret), which exchanges codes and refreshes tokens for the app. Callback URLs must be **HTTPS or localhost**, so: `http://localhost:<port>/callback` for desktop, and for mobile an HTTPS bounce page on the project's GitHub Pages site (next to the firmware feed) that forwards `code`/`state` to `inkframe://supabase-oauth`. Safe with PKCE: the code is useless without the verifier, which never leaves the device.
- **Google Cloud:** OAuth client IDs for **iOS, Android, Web, Desktop**.
- **Apple Developer:** App ID with Sign in with Apple.
- These IDs go in the app's build config (`app/lib/config/`, plus per-platform files). Nothing secret is embedded unless §14 forces it.

### 6.2 Wizard steps ("Set up a frame")
Built in 3e: `app/lib/data/provisioner.dart` runs these steps (each safe to repeat; progress saved after each, so setup resumes), `test/live/provision_live_test.dart` runs them against the real API (~35 s).
1. **Connect Supabase:** authorization code + PKCE in the system browser; the code exchange and refreshes go through the directory Worker, which adds the client secret (spike c). In dev, a **PAT** can be pasted instead (a dev-only setting; such setups keep email sign-in for developer sign-in).
2. **Create the project** in the account's organization (OAuth: the one chosen at consent), region `smartGroup` from the time zone (`POST /v1/projects`; the generated DB password isn't kept, nothing needs it). Poll `GET /v1/projects/{ref}` and `/health?services=db,auth,rest,storage` until healthy (measured ~4 s; keep a progress screen in case it's slower).
   - The free plan allows **2 active projects per account**, so an owner can run 2 frames. If the limit is hit, show a clear message (another family member can set up the next frame with their own account).
3. **Apply migrations:** run the bundled SQL from `backend/supabase/migrations/` through `POST /v1/projects/{ref}/database/query`, in order, recording `schema_version`. This creates tables, RLS, buckets and policies, cron jobs and seed data.
4. **Deploy the Edge Functions** `device-api` and `app-api` through the Management API's multipart deploy (`POST /v1/projects/{ref}/functions/deploy`): the app uploads the function **source files** it bundles as assets, and Supabase bundles them server-side (`tools/dev/deploy-functions.ts` is the reference).
5. **Configure auth** through `PATCH /v1/projects/{ref}/config/auth`:
   - enable Google (all our client IDs) and Apple (bundle ID)
   - turn off email signup
   - set the JWT expiry and site/redirect URLs if needed
6. **Describe the frame** with SQL (`private.setup_frame(name, model_id, timezone)`): name, **panel model** (picked in the wizard) and time zone.
7. Fetch the project URL + publishable key (`GET …/api-keys` without `reveal`, so the secret key never reaches the app) → the owner signs in with Google/Apple (a recent sign-in is reused) → `private.set_owner(user_id, display_name)` (the name is asked on the form) → the frame goes on the device and on the owner's directory list.
8. **Connect the frame** over BLE (§9.5, Phase 3f). Photos can be added before the hardware arrives.
9. Keep the platform **refresh token** (prod) in secure storage on the owner's device only.
10. After deploying functions, the frame's `private.config` `backend` = the bundle's fingerprint, so **Update** is offered for a newer schema or the same schema with different functions (never back to an older schema).

### 6.3 Schema upgrades
- Every app release bundles all migrations. On launch the app reads `schema_version`:
  - **Owner's app:** runs any pending migrations and redeploys the functions, after asking the owner to confirm.
  - **Member's app on an older schema:** runs in compatible mode or shows "Ask \<owner\> to open the app to update."
- Rule: migrations must stay backward compatible with the previous app version.

### 6.4 Paused projects
- **App:** detects a pause from **HTTP 540** ("Project paused") on any function call, plus Management API status on the owner's device. Restore takes ~3 min (measured), and the functions may return 500 for a few seconds after the project is healthy. The owner gets a **Wake up** button (`POST /v1/projects/{ref}/restore`); members see "Ask \<owner\>". Copy explains the reason: *"This frame's photo storage is asleep because it wasn't used for a while."*
- **Frame:** keeps showing cached photos and retries on its backoff.
- Daily frame syncs should prevent a pause (verify, §14). With one project per frame, each frame keeps its own project awake.

---

## 7. Backend package (`backend/supabase/`)

The same package is deployed to the dev project (through the CLI) and to every family project (through the wizard).

### 7.1 Schema
Implemented in `backend/supabase/migrations/` (0001 tables, 0002 access, 0003 jobs, 0004 operations). One project holds **one frame**. Tables in `public` are readable by members under RLS; secrets and server-only state live in the unexposed `private` schema.

| Table | Key columns / notes |
|---|---|
| `schema_version` | `version int pk`, `applied_at` |
| `palettes` | `id`, `name`, `colors jsonb` (`[{name, color, deviceColor}]`, same shape as `presets.json`) |
| `device_models` | `id` (e.g. `reterminal-e1002`), `name`, `width`, `height`, `palette_id`. Upserted by `seed.sql`, generated from `shared/presets.json` |
| `frame` | **One row** (enforced). `id uuid`, `name`, `model_id` (chosen at setup), `hw_id` (null until hardware connects), `fw_version`, `manifest_version bigint`, `last_seen_at`, `battery_pct`, `rssi`, `sd_free_bytes`; settings: `image_interval_s` (14400), `display_order` (`random`/`sequential`), `sync_interval_s` (86400), `quiet_start`/`quiet_end` (both or neither), `timezone` (IANA), `settings_updated_at`; `created_at`; `synced_manifest_version` (set by `/sync`) and generated `up_to_date` (hardware has the latest photos and settings) |
| `members` | `user_id pk → auth.users`, `role` (`owner`/`member`; **exactly one owner**, partial unique index), `display_name`, `invited_by`, `created_at` |
| `images` | `id uuid`, `uploaded_by` (nullable, `on delete set null`: photos outlive a deleted account), `storage_path`, `sha256` (unique), `bytes`, `width`, `height`, `position double` (set when `ready`), `status` (`pending`/`ready`), `created_at` |
| `invites` | `id`, `created_by`, `expires_at`, `max_uses`, `uses` |
| `quota_config` | `scope` (`frame`/`user`), `max_images`, `max_bytes` (null = unlimited). Placeholder: frame `max_bytes` = 90% of 1 GiB |
| `private.frame_secret` | the connected device's `secret_hash` (SHA-256 hex) |
| `private.removed_devices` | `secret_hash pk`, `removed_at`. Tombstone for a disconnected or replaced device, so `/sync` answers `410` instead of `401` |
| `private.invite_codes` | `invite_id pk`, `code_hash` |
| `private.pairing_tokens` | `token_hash`, `user_id`, `expires_at` (10 min), `used_at` |
| `private.config` | key/value: `maintenance_secret`, `project_url` (written by the migration runner) |

- The wizard (and the tests) describe the frame and add the owner with SQL: `private.setup_frame(name, model_id, timezone)`, `private.set_owner(user_id, display_name)`.
- **RLS:** members can `select` the frame, members, ready images (and their own pending ones) and quotas; invites are visible to the owner. **All writes go through `app-api`** (service role). Clients get `SELECT` grants only; Supabase's default grants on `public` are revoked, so every new table or function must be granted explicitly.
- **Permissions:** photos: a member deletes their own, the owner deletes any. Frame name, model, settings, reorder, connecting hardware, invites and removing people: owner.

### 7.2 Storage
- Private bucket `frame-images`, path `{image_id}.png`.
- Max 512 KB per object; MIME type `image/png` only.

### 7.3 `device-api` (auth: `Authorization: Bearer <device_secret>`, compared by SHA-256 hash)
- **`POST /claim`** `{pairing_token, hw_id, model_id, fw_version}` → `{frame_id, device_secret}`. The secret is 32 random bytes, returned once.
  - `model_id` must equal the frame's model, else **`409 model_mismatch`**.
  - Same `hw_id` as connected (re-provisioning): new secret, old one stops working (`401`).
  - Different `hw_id` (replacement, same model): the new hardware takes over and keeps the photos; the old device's secret is tombstoned, so it gets `410` and wipes itself.
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
  - Returns **`410 Gone`** if this device was disconnected or replaced. The frame then wipes itself.

### 7.4 `app-api` (auth: Supabase JWT + `members`)
**Frame (owner)**
- `PATCH /frame` `{name?, model_id?, clear_photos?}`. Changing the model deletes all photos (and needs `clear_photos: true` when there are any) and disconnects the current hardware.
- `PATCH /frame/settings`.
- `POST /pairing-tokens` → one-time token (10 min) for connecting hardware.
- `POST /frame/disconnect` → the device gets `410` at its next sync.

**Photos**
- `POST /images/request-upload` `{sha256, bytes, width, height}`: checks membership, dimensions against the frame's model, quotas and dedupe; inserts a `pending` row and returns a signed upload URL.
- `POST /images/finalize` `{image_id}` → checks the object exists, its size, PNG signature and IHDR dimensions → `ready`, bumps `manifest_version`.
- `POST /images/delete` (own photos, or any for the owner), `POST /images/reorder` (owner).

**People**
- `POST /invites` (owner), `DELETE /invites/{id}` (owner), `POST /invites/accept` `{code, display_name}`.
- `DELETE /members/{user_id}`: the owner removes someone, or a member leaves. Their photos stay.

**Account and usage**
- `PATCH /me` `{display_name}`.
- `GET /usage` → the frame's storage + limits, and per-person usage (everyone for the owner, yourself otherwise).
- `DELETE /me[?delete_photos=true]` → a member leaves and deletes their account (App Store requirement). **"Also delete my photos" checkbox** sets `delete_photos`; unchecked, the photos stay with `uploaded_by` → null. The owner gets `409 owner_must_delete_frame`: the app instead offers to delete the whole frame (its project) through the Management API, after a warning.

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
5. **Indexed PNG encoder** (`lib/imaging/png_encoder.dart`, `zopfli.dart`), tuned for the smallest files:
   - IHDR colour type 3 with the fewest bits for the colours **actually used** (1 bit for 2, 2 for ≤4, 4 for ≤16); `PLTE` = those colours' `deviceColor`s; no tRNS or other chunks
   - row filter **none** (every other filter and the per-row heuristic came out larger on dithered images), 4-bit packing (8-bit is ~4 % larger)
   - a few zlib-9 candidates pick the palette order and strategy, then the winner is recompressed with a **Dart port of Zopfli** (optimal parsing, block splitting, length-limited Huffman): another 5–9 %
   - measured on 12 real photos at 800×480, Spectra 6 (`test/imaging/png_bench_test.dart`): Floyd–Steinberg **57 KB** (ink-frame-lab's 24-bit PNG: 135 KB), Atkinson 52 KB (122), ordered 25 KB (59); about 1 s per image on a Mac, within 0.4 % of the reference Zopfli
5a. **Automatic** (the default look; user request 2026-09-26: opendithering's Auto-tune as the default, "improved if possible to get closer to the source"; `lib/imaging/auto.dart`):
   - opendithering's pipeline and Auto-tune are ported exactly (`od_pipeline.dart`, `autotune.dart`; parity on 28 pipeline and 4 Auto-tune vectors) and kept for comparison.
   - A fidelity score (`fidelity.dart`) measures closeness to the source as seen on the panel: panel colours adapted to the panel's white, both images blurred in linear light, mean OKLab ΔE×100 (plus SSIM of lightness for detail).
   - On 12 real photos (Spectra 6, measured palette / our preset palette): ink-frame-lab Floyd–Steinberg 23.3 / 15.9; opendithering Balanced 9.4 / 8.8; **opendithering Auto-tune 16.3 / 10.5** (it matches absolute chroma, oversaturating relative to the panel's grey-ish white, and casts skin and shadows blue/teal).
   - Improvements that measured better, and are what Automatic does: map the photo's black/white to the panel's **per channel in linear light** (media-relative, like print colour management), with **black mapped to the darkest neutral the panel can mix** (removes the purple cast of the panel's black in shadows; chosen on visual comparison); **diffuse error in linear light** (how the eye blends dots); then a **per-photo tuner** (exposure, colour, contrast, shadow lift) that minimises the fidelity score on a half-size copy. Result: **4.7–5.1 / 3.5**, detail (SSIM) unchanged, ~1.4 s per photo in a debug build.
   - **Cost, and how Prepare hides it** (measured 2026-10-02 on an Apple-silicon Mac, 800×480; debug and release builds are within ~25 % of each other because the work runs in isolates): Automatic's search ~1.0–1.3 s per photo and crop; rendering with known settings ~50 ms; crop and resize ~10–20 ms. Phones are expected to be 2–4× slower. So Prepare (`features/prepare/prepare_session.dart`) uses two lanes: a **quick lane** renders the frame look 80 ms after a slider change (150 ms after a crop change) using Automatic's last settings for that photo (or the untuned baseline for a new photo), and keeps showing the previous look with "Updating…" meanwhile; a **slow lane** runs the search in its own isolate once the crop has been still for 500 ms, then the quick lane swaps in the tuned look. Moving the crop again kills a search that's under way. No "Apply" button (beginners forget to press it).
   - Adjust (hidden by default) offers Brightness, Contrast, Colour around Automatic's choice and a dot pattern (Fine = FS, Smooth = Jarvis, Crisp = Atkinson, Grid = ordered 4×4, Grainy = random).
6. **sha256** of the PNG bytes → `request-upload` → PUT to the signed URL → `finalize`.

Dithering options follow ink-frame-lab (algorithm, kernel, serpentine, Bayer size, random type), with a default preset per model.

### 8.4 Golden parity tests
- `tools/golden/` (Node): loads `reference/ink-frame-lab/js/dithering.js` with an `ImageData` polyfill. Runs every mode and kernel on fixed **pre-resized RGBA** inputs. Writes index arrays to `shared/test-vectors/`.
  - Inputs are pre-resized so resize differences don't count.
- **Dart tests** must match those **exactly** for quantization, ordered, and every ED kernel (serpentine on and off). Random mode is checked statistically.
- **Encoder tests:** the output decodes back to identical indices (decode with `package:image` in tests only), is a valid PNG, and its size is logged.

### 8.5 Questions Phase 2 must answer (input for the planning session)
- The first-run experience: set up a frame vs join one by invite; how the wizard's progress and failure states look.
- Navigation model: frames → photos; tabs vs drill-down; desktop layout (multi-pane?) vs mobile.
- The add-photos flow: batch picking, per-photo crop, dithering adjustments (how much control?), preview, upload queue and retry.
- How the frame screens show status (last sync, battery, "changes arrive at next sync / press green").
- Usage display (project storage vs free-tier limit, per-frame and per-user), warnings, and what happens at the limit.
- Invite UX: QR, share sheet, desktop paste; member management; roles shown.
- Settings UX: intervals, order, quiet hours, timezone.
- Add-frame (BLE) flow and its error states: Bluetooth off, wrong passkey, wrong Wi-Fi password, claim failed.
- Owner tools: schema upgrade prompt, wake up a paused project, delete the frame.
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
  - Built (4a): photos in `/cache/<first 2 hex>/<id>.png` (FAT looks names up one by one; 256 folders keep each small), `/cache/newest.txt` (just-arrived ids, shown first), downloads in `/cache/tmp/<id>.part` (size + SHA-256 checked, then moved). Nothing outside `/cache` is ever touched (e.g. a card's old `/images`).
- **The memory card** (added 2026-10-04): FAT16/FAT32 up to 2 TB (Arduino-ESP32 2.0's FatFs: no exFAT, 32-bit sectors). States `ok` / `missing` (detect pin, or no answer) / `unreadable` (answers but no FAT: exFAT, NTFS, damaged), shown on the e-paper and reported (`info.sd`, `/sync` `sd_total_bytes` 0). A card that won't mount is powered off and on and retried, at 20 MHz then 4 MHz. **Erase** (`provision.erase_sd`) formats FAT32 over the whole card (FAT16 if too small; a 256 KB PSRAM work buffer, so a large card takes under a minute), which also fixes an unreadable or exFAT card. The frame keeps 8 MB free: obsolete photos are deleted first, then new ones download in list order while they fit; the rest are skipped (the list version isn't advanced, so the next check retries) and the app warns from `/sync`'s `sd_free_bytes` + `cache_bytes`. A new or swapped card has no manifest: the frame asks for the full list (`manifest_version` 0).
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
- **`410`:** wipe the cache and secret → screen "Not connected to an album. Hold the green button for 3 seconds, then connect it in the Ink Frame app."
- **Empty manifest:** "Ready. Add photos in the Ink Frame app."

### 9.5 BLE pairing (NimBLE custom GATT + LE Secure Connections)

Specified in [docs/pairing.md](docs/pairing.md) (UUIDs in `shared/pairing.json`); in short:
1. Entering PAIRING creates a random 6-digit **static passkey** and shows it on e-paper with the name `InkFrame-XXXX` and short instructions. It advertises (service UUID; the name in the scan response) for 10 min, then sleeps.
2. Characteristics, all needing an encrypted, authenticated link (so the first read triggers pairing); messages are one line of JSON ending in `\n`, split into MTU − 3 chunks:
   - `info` (read: `hw_id`, `model_id`, `fw_version`, `frame_id` it's linked to or null)
   - `wifi_scan` (write `{"scan":true}`; notify: one network per message, then `{"done":true}`)
   - `provision` (write: `ssid`, `password`, `api_base_url`, `pairing_token`)
   - `status` (notify: `wifi_connecting`, `wifi_failed` + `reason` (`auth`/`not_found`/`other`), `claiming`, `claimed`, `syncing`, `ready`, or `error` + `code`)
3. The link is encrypted by OS pairing with the passkey shown on screen, so the password and token are never sent in plaintext. The frame keeps no bonds; the app removes the OS's bond when it's done (where the OS allows).
4. Join Wi-Fi → `POST /claim` → store the secret → notify `claimed` → first sync → `ready` → ready screen, leave PAIRING.
5. Hardware still linked to another frame (`frame_id` from `info`, or `api_base_url` differs) is refused (`linked_elsewhere`) until a 10-s reset.

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
   - (c) Supabase OAuth App + PKCE without a client secret. **Deferred to the start of Phase 3e** (nothing earlier depends on it); script ready in `tools/dev/oauth-connect.ts`, needs the user to register the OAuth App first (§6.1).
7. `tools/frame_sim` (Dart CLI): `claim --token`, `sync` (keeps a local cache dir mirrored), `status`, `render` (writes the current image + a manifest summary), `reset`. Also `tools/dev` scripts: `migrate`, `deploy-functions` (raw API), `provision` (the wizard's steps), `delete-project`, `gen-seed`, `gen-tz`, `oauth-connect` (spike c) and `sim-scenario` (§12.1 with `frame_sim`). A separate "bundle the backend" step isn't needed: the app ships the migration and function **sources** as assets (copied in Phase 3e). "Upload test PNGs as a user" and "reset the dev project" are left until Phase 3 needs them.
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
- **3c** Core screens per `docs/app-flow.md`: frames, photos (add/crop/preview/upload/delete/reorder), settings, usage.
- **3d** Invites and members; display names.
- **3e** Spike (c) first (user registers the Supabase OAuth App; run `tools/dev/oauth-connect.ts`). Then the provisioning wizard (PAT in dev → OAuth in prod), schema upgrade, wake up, delete frame.
- **3f** BLE add-frame flow (app side). Before hardware exists, the dev-mode "pair with token" path and `frame_sim` stand in for the frame, and `tools/ble_frame` (a pretend frame over real Bluetooth).
- **Exit:** the §12.2 scenarios pass on Windows desktop and on at least one phone.

### Phase 4 — Firmware (Claude + User with hardware)
- **4a** PlatformIO port (§9.1–9.2), SD cache, sync + mirror, settings, quiet hours. Temporary serial provisioning (Wi-Fi/URL/secret over UART).
- **4b** BLE pairing (§9.5) end to end with the app; the serial console only in developer builds (§16).
- **4c** OTA + signed central feed + release CI (§10).
- **Exit:** the §12.3 matrix passes on a real E1002.

### Phase 5 — Hardening and release
- Privacy policy, App Store / Play listings, TestFlight / internal testing, account and space deletion checks, battery measurements, docs for families.

---

## 12. Verification

### 12.1 Backend (Phase 1B)
Implemented in `backend/supabase/tests/backend_test.ts`. The suite sets up the project's frame and owner itself, so it **skips when the target project already has an owner**: once the developer owns the dev frame (Phase 3), run it against a throwaway project (`tools/dev/provision.ts`). The scenario also runs with the real `frame_sim` binary: `tools/dev/sim-scenario.ts` (same requirement).
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
  7. disconnect the frame (or connect replacement hardware) → the old device gets `410`

### 12.2 App (Phase 3)
- Golden parity (§8.4) passes in CI.
- **On Windows desktop:**
  1. dev PAT → the wizard sets up a fresh frame in the spare project slot
  2. sign in with Google (loopback)
  3. drag in 5 photos → crop/preview → upload
  4. `frame_sim sync` receives them
  5. delete one → `frame_sim` mirrors
- **On a phone:** join through the invite QR → Apple (iOS) or Google sign-in → type a display name → upload → `frame_sim` receives it with the right uploader.
- The usage view matches `GET /usage`.

### 12.3 Firmware (Phase 4) on a real E1002
- **Pairing:** wrong Wi-Fi password; wrong passkey.
- **Sync:** add, delete and reorder → forced sync (green press); settings change; quiet hours across midnight.
- **Failures:** Wi-Fi down / server 500 / paused project (backoff; cached photos still shown); `410` wipe; power cut mid-download (tmp file never shown); SD full.
- **OTA:** success; bad hash; bad signature; rollback.
- **Decoding:** 4-bit palette PNGs from the app decode correctly.
- **Battery:** measure sync duration and current with a USB power meter and estimate battery life.

### 12.4 End to end
Fresh owner → wizard → connect the frame over BLE → upload → press green → the photo appears. A second user joins through an invite → uploads → the frame shows it at its next sync. Leave the frame's project with only daily frame syncs for more than 7 days and confirm it isn't paused.

---

## 13. Progress checklist
- [x] Phase 0 — scaffold
- [x] Phase 1 — Supabase account + PAT available to sessions (user). Dev project `ink-frame` (ref `vrhsxzedzhvujnirsuhg`, `ap-south-1`); token in `backend/.env.local`. Google client IDs (web, iOS, desktop; Cloud project `ink-frame-510506`) and Apple team `48QFANT8RD` with Sign in with Apple added 2026-10-03 (`shared/oauth-clients.json`); Android client (debug key SHA-1) added the same day
- [x] Phase 1B — contract ✅ · migrations ✅ · device-api ✅ · app-api ✅ · tests ✅ · dev project deployed ✅ · spikes (a) ✅ (b) config ✅ (c) ✅ 2026-10-03 (needs the secret → Worker; any account can approve) · frame_sim ✅ · dev tools ✅
- [x] Phase 2 — `docs/app-flow.md` approved 2026-09-26 (D1–D5, D7–D11 as recommended)
- [ ] Phase 3 — 3a (built; Google sign-in works on Android and macOS; Apple sign-in, iPhone and Windows to try) · 3b ✅ · 3c (built; tried on desktop and Android) · 3d (built 2026-10-03; to try on the phone: join by QR) · directory ✅ (deployed 2026-10-03 at `ink-frame-directory.psmyles.workers.dev`; Google alone finds the frames on Android and macOS) · 3e ✅ (Set up a frame works with a second Supabase account, 2026-10-03) · 3f ✅ (live connect test; Connect the frame on Android against `tools/ble_frame` over real Bluetooth, 2026-10-04; pairing with a real frame's code is 4b) · 3g (built 2026-10-04; to try: the more-frames card, the battery notification on a phone; Phase 3 exit still needs Windows and iPhone) · backend suite and the app's live tests ✅ on a throwaway project 2026-10-04 (incl. watch tokens, the test-only second model, the memory-card fields)
- [ ] Phase 4 — 4a ✅ (2026-10-04: PlatformIO project, display/SD/PNG ported, cache + sync + mirror, settings, quiet hours, backoff, the memory-card cases, serial console for provisioning; native unit tests; on the E1002: linked over USB to a test album, photos shown, deletes mirrored, a swapped card re-downloads everything; the other hardware checks verified by the user) · 4b (built 2026-10-04: NimBLE-Arduino 2.5.1, the pairing service, the code on screen, setup loop with the console alongside in developer builds; advertising checked on the E1002; Connect the frame from a phone to try) · 4c
- [ ] Phase 5 — release

---

## 14. Verify list (assumptions not yet confirmed; check before relying on them)
- Supabase free-tier limits today (storage, egress, DB size, Edge Function calls, MAU), the **2 active free projects** rule, and whether daily Edge Function + DB traffic from a frame counts as activity against the **7-day inactivity pause**.
- ✅ ~~Management API coverage~~: all confirmed with a PAT, see `docs/spikes/a-management-api.md`. **Exception:** no storage-size or egress endpoint (only hourly request counts), so the app shows storage from the database and can't show egress. **2 active free projects** rule confirmed (400, message quoted in the spike doc).
- ✅ ~~Supabase OAuth App: whether PKCE works without a client secret~~: **it doesn't** (`422 Required parameter: client_secret`, `docs/spikes/c-supabase-oauth.md`), so the token exchange and refresh go through the Cloudflare Worker, which holds the secret. An account **outside** the developer's org approves the app as registered (no publishing needed; tested with a second account). Still open: the scopes to keep.
- Google provider: native ID-token sign-in **without a client secret**, and several client IDs (iOS, Android, Web, Desktop) allowed at once. Apple provider: bundle ID only for native. **Config part ✅** (accepted with no secret; IDs stored as one comma-separated list, `docs/spikes/b-auth-config.md`). Actual sign-in: **Google on Android ✅** (2026-10-03, Galaxy A55, joined the dev frame by invite link); macOS (Google, Apple), iOS and Windows still to try.
- Mobile OAuth redirect via an HTTPS bounce page on GitHub Pages (§6.1): the Supabase OAuth App accepts it as a callback URL, and the system browser hands `inkframe://` back to the app on iOS and Android.
- Windows desktop: the Google loopback PKCE flow, and whether `universal_ble` can do LESC passkey pairing on Windows (and macOS).
- ✅ ~~Whether the Edge Functions gateway needs the anon key as `apikey` for device calls.~~ **No**, with `verify_jwt = false` (2026-09-25), so frames don't store `anon_key`.
- ESP32 newlib: parses POSIX TZ strings with angle-bracket names (e.g. `<+1030>-10:30<+11>-11,M10.1.0,M4.1.0`), as produced by `_shared/tz.ts`.
- ✅ ~~PNGdec: 4-bit indexed PNG through `getLineAsRGB565`.~~ Works (2026-10-04: the test photos are 4-bit indexed and show correctly on the E1002).
- Arduino-ESP32: bootloader app rollback support.
- E1002: status-LED GPIO; whether there is an external RTC (use it for quiet hours if present).
- Google sign-in on Windows/Linux: the Desktop client's token exchange with PKCE, and whether Google still requires the (public) client secret. Implemented with an optional `GOOGLE_DESKTOP_CLIENT_SECRET`; verify once the client IDs exist.
- Whether a frame's daily `/sync` (Edge Function calls) counts as activity for Supabase's free-tier pausing. If it does, a frame with a flat battery lets its project fall asleep after a week, which the low-battery alert (§15) is meant to prevent.

## 15. Open decisions (defaults used until changed)
- **Moving hardware to a different frame (another owner's project):** a **factory reset (hold 10 s)** frees it locally; the old frame shows it as not seen, and its owner can disconnect it.
- **Who changes frame settings:** the owner only.
- **Order of photos from several people in sequential mode:** default is upload time; the owner can reorder.
- **Quota starting values:** `quota_config`, to be decided (placeholder: frame ≈ 90% of the free storage limit; no per-person limit).
- **Apple sign-in on Windows/Linux:** decided in Phase 2.
- **Confirmed by the user** (2026-09-25, restated for one project per frame on 2026-09-26):
  - ✅ **One project per frame; one owner** (who set it up and hosts it). No handover of ownership.
  - ✅ Someone who leaves or is removed: **their photos stay**; the owner can delete them.
  - ✅ A member deleting their account deletes only the account and membership; photos stay (`uploaded_by` → null) unless they tick **"Also delete my photos"**.
  - ✅ The owner deleting their account means **deleting the frame** (its whole project), after a clear warning.
  - ✅ **Panel model chosen at setup.** Replacement hardware of the same model keeps the photos; a different model needs the owner to switch the frame's model, which clears the photos.
  - ✅ Reorder moves **one image at a time** ("place after X").
  - ✅ Settings ranges: image interval **1 h–2 days**, default **4 h**; sync interval **1 h–2 days**, default **24 h**.
  - ✅ Invites (owner only): single use and 7 days by default; at most 50 uses and 30 days. Codes are 10 Crockford base32 characters (`XXXXX-XXXXX`).
  - ✅ Re-connecting the same hardware (green held 3 s) keeps the frame, its photos and settings, and issues a new secret.
  - ✅ Pause copy gives the reason: "asleep because it wasn't used for a while".
- **Low-battery alert** (user request 2026-09-26). The frame already reports `battery_pct` on every `/sync`, and the app shows "Battery low" below 20 %. To add: a notification when a frame's battery falls below a level, so it's recharged before it stops checking in (and before its project could fall asleep, §14). Proposed: **local notifications** from a background refresh in the app (iOS background fetch, Android WorkManager) that reads each frame's `battery_pct`, with the level set per frame by the owner (default 20 %, stored on `frame`), rather than server push, which would need the developer's FCM/APNs credentials in every family's project. Schedule: Phase 3d (setting) and 3g (background refresh). **Confirmed by the user 2026-10-03; the setting is built** (`frame.low_battery_pct`, migration 0005; app-only, so it doesn't make the frame "Changes waiting"; Off turns the status warning off too). Who gets the notification is decided in 3g (default: the owner). **Built in 3g (2026-10-04):** each person chooses per phone ("Notify me when it's low", on by default for the owner), and the background check reads the frame with a read-only **watch token** per device and person (`POST /app-api/watch-tokens`, `GET /app-api/watch`, migration 0006), never with the sign-in session (its refresh token rotates; a background refresh racing the app would sign the person out).

## 16. Decision log
- 2026-10-04: **Phase 4b built** (Bluetooth setup, docs/pairing.md). NimBLE-Arduino 2.5.1 (builds against Arduino-ESP32 2.0.17; RAM 35 %, flash 1.3 MB). Setup makes a random 6-digit passkey, starts advertising, then draws the screen (name, its 4 characters and the code in two boxes), so a phone can connect during the ~20 s refresh. LE Secure Connections, display-only, MITM; it **bonds for the session** (phones expect bonding) and deletes every bond when setup starts and ends, which keeps "a new code each time". Requests from the NimBLE task go through a queue to the main loop, so joining Wi-Fi and claiming never block Bluetooth; notifications are split to MTU − 3 and retried if the stack is out of buffers. Advertising lasts 10 minutes without a connection (at most 30 with one); then the screen is redrawn without the code and the frame sleeps until the green button. After `ready` the frame doesn't check again (linking just did). **The serial console stays, in developer builds only** (`INKFRAME_CONSOLE`, default 1; release builds will set 0 in 4c), and runs alongside Bluetooth in setup; PLAN.md §11 said to remove it. Found while trying it: the frame was still linked to the deleted throwaway project, whose address no longer exists, so its checks just fail (no 410 once the name is gone) and Connect would say "still linked to another album"; a factory reset fixed it. A frame whose album was deleted while it was offline for long has the same problem; to revisit (e.g. after many days of "address doesn't exist" while the internet works).
- 2026-10-04: **Connect Supabase on Android stayed on "Returning to Ink Frame…"** (user, Galaxy A55 with Firefox as the default browser). The app did get the code: flutter_web_auth_2's CallbackActivity hands it over as it opens. But browsers without Chrome's Auth Tab open their tab in the app's task and send `inkframe://supabase-oauth` to a new task, where the plugin's "close the tab" step (an activity started with CLEAR_TOP) can't reach the tab, so it stayed over the app; "Open Ink Frame" just repeated that. The app now declares its own `OAuthCallbackActivity` (Kotlin) in place of the plugin's: it hands the link to the plugin the same way, then starts `MainActivity` with NEW_TASK | CLEAR_TOP | SINGLE_TOP, which finds the app's task (no task affinity → matched by activity) and closes the tab above it. Chrome (Auth Tab) never reaches it.
- 2026-10-04: **Album and frame** (user: "the frame and the test frame are quite conflicting and confusing terms for an end user"). "Frame" meant both the photos, people and storage and the hardware on the wall, and "device" already means the phone or computer. Now the app says **album** for the first (what has the name, the people, the photos and the storage: "Join an album", "Delete this album", "Albums" on Home) and **frame** only for the hardware ("Connect the frame", its buttons, battery, Wi-Fi and memory card). Rule: if it would still exist after the hardware was thrown away, it's the album. Settings groups into **Album** (name, storage) and **The frame** ("Frame F7C4", the 4 characters its setup screen shows, from the last 4 of `hw_id`; software and battery; memory card; model; Connect a different frame / Disconnect), then Showing photos, Checking for new photos and Battery. The same pass made other text plainer at the user's request: "Revoke" → "Cancel invite", "Connect new hardware" → "Connect a different frame", "Changes waiting · next check around 18:00" → "The frame gets the changes around 18:00", exFAT left out of the unreadable-card message, a "5G" tip on the Wi-Fi step, and sign-out now says the albums come back on signing in again. The frame's own screens follow ("Not connected to an album" after a 410; setup points to Set up a frame or Connect the frame). Code names (`frame` table, `Frame`, the API) are unchanged; string keys that now mean the album were renamed (`deleteFrame` → `deleteAlbum`, …). Still one album per frame (one project per frame), so Connect still says a new frame replaces the one showing the album.
- 2026-10-04: **The frame's memory card** (user: the card could be smaller than the photos; show its capacity and use; offer to format it at setup; handle file systems and capacities). Contract 2.2.0: `/sync` also sends `sd_total_bytes` (0 = no card or unreadable) and `cache_bytes`; both are stored on `frame` (migration 0007) with `sd_free_bytes`. The app shows "Memory card: 2 GB of 32 GB used · its photos take 312 MB" in Settings, "No memory card" under the status, and a notice when the photos don't fit (total > free + cache − 8 MB). Pairing: `info.sd` (`ok`/`missing`/`unreadable` + sizes, `other_bytes` for files that aren't the frame's) and `provision.erase_sd` (status `erasing`, error `sd_failed`); Connect the frame's Wi-Fi step shows the card and **Erase the memory card first** (on by default for an unreadable card). Firmware handling in §9.3. Checked on the E1002: its 32 GB card reads as 30.4 GB FAT32; exFAT isn't supported by the core's FatFs (`FF_FS_EXFAT 0`), which is why erasing formats FAT32 (FatFs `f_mkfs`, also on cards over 32 GB).
- 2026-10-04: **Phase 4a built** (`firmware/`). Platform `platformio/espressif32@7.1.3` (Arduino-ESP32 2.0.17), board `seeed_xiao_esp32s3`, C++17. Measured on the user's E1002: ESP32-S3 rev 0.2, 8 MB PSRAM, 32 MB Winbond quad flash; the partitions use 16 MB (Arduino 2.0 addresses 16 MB with 3-byte commands): two 6 MB app slots for OTA, NVS, coredump. HTTPS checks certificates with the Mozilla bundle already in the core's mbedTLS (`_binary_x509_crt_bundle_start`). Logs and the console on UART0 (GPIO43/44 = the USB-C port's CH340), so USB-CDC is turned off. Provisioning (4a) is a JSON-lines serial console that speaks the Bluetooth messages (`info`, `wifi_scan`, `provision` → the same `status` sequence), so 4b only swaps the transport; `firmware/tools/console.py` drives it and `tools/dev/usb-connect.ts` links the frame to a test frame on a throwaway project (the Wi-Fi password is typed into the console, never passed through the tools). Pure logic (schedule, photo list, what fits) has native unit tests (`pio test -e native`).
- 2026-10-04: **Only the reTerminal E1002** (user's request). `shared/presets.json` keeps one device (the palettes stay: they're colour calibration, and the golden vectors use them); the seed and the app's bundled model list now have `reterminal-e1002` only. The seed never deletes models, but no project had another one (all were deleted). Setup's model list has the one entry, pre-selected; Settings hides **Change** next to the model while there's one. The model-switching code stays for later models: the backend and live tests add a test-only `test-other-7-3` model (`backend/supabase/tests/_lib.ts`, removed again by cleanup), and the app's widget tests use a fixture "Test panel 7.3\"". The pretend frame always reports the E1002 (its model menu is gone).
- 2026-10-04: **Connect the frame asks you to match the frame before connecting** (user: "no indication that something happened, it just jumps to the next screen", tried with the pretend frame, which can't do the passkey prompt). Options weighed with the user: Bluetooth numeric comparison (phone and frame show the same 6 digits during pairing) was turned down because that code only exists once pairing starts, so the frame would have to redraw its e-ink screen (~20 s) inside Bluetooth's ~30 s pairing limit; an in-app 6-digit check was turned down because the code would travel before the link is encrypted (no security, and a second check on top of the real prompt). Chosen: the app no longer auto-picks a single frame; it shows "Is this your frame?" with the frame's `XXXX` large (Yes, connect / Not this one? Look again), a list with each `XXXX` for several, then "Connecting to InkFrame-XXXX…" and "✓ Connected to InkFrame-XXXX" above the Wi-Fi list. Security is unchanged: the real frame's passkey entry (the phone asks for the 6 digits on the frame) still encrypts the link. Firmware (4b): show `XXXX` large on the PAIRING screen next to the passkey.
- 2026-10-04: **Welcome starts with signing in** (user's request). Was: "I've been invited" / "Set up a frame" / "Already use Ink Frame? Sign in". Now Welcome shows only Continue with Google/Apple (email in developer mode); the app then asks the directory for the account's frames and signs in to each → Home. With none: "No frames yet" with **I've been invited** / **Set up a frame**, which reuse that sign-in, and **Use a different account**. If the frames couldn't be looked up (offline, directory down, a frame asleep) the same screen says why with **Try again**, so setting up or joining is never blocked. The frame lookup moved out of the Join screen (its "find" step is gone; Join keeps the link → sign-in → name steps, for invite links opened from outside and "Sign in again"). Sign out and Delete my account now forget the recent sign-in and Google's chosen account. The "logged in" state is the recent ID token (in memory, ~50 min), not stored: after a restart with no frames, Welcome asks to sign in again, which also looks again. Setup no longer reuses a developer email sign-in on a project without email sign-in.
- 2026-10-04: **A frame whose project was deleted.** Found when the user deleted every project: a just-deleted project answers HTTP 410 "Project removed." (plain text); some time later its address stops existing (NXDOMAIN) while `api.supabase.com` still answers. The app showed such a frame as offline or signed out, with no way to remove it. Now, when a frame can't be read (and isn't asleep or removed), `FrameConnection.isGone` asks: 410 from `/auth/v1/health`, or the host lookup fails while Supabase answers → **"Kitchen no longer exists: its photo storage was deleted."** with **Remove from this device**, which also takes it off the account's directory list (same button now used for "You're no longer on this frame"). Home says "No longer exists". Find your frames / Add to this device skip deleted frames instead of failing; joining one says it no longer exists; the battery check stops checking it. Fixed alongside: restoring a session whose refresh got no answer (offline, or 540 asleep) deleted the saved session, so opening the app offline more than an hour after last use signed you out of the frame, and an asleep frame showed "signed out" instead of "Wake up"; the session is now kept and tried again. Signing in to an asleep frame also said "offline" (auth's 540 is a retryable error); now it says asleep.
- 2026-10-04: **Phase 3g built.** (1) **Your frames on all your devices:** the app reads the directory (`GET /v1/frames` with the device token) at start and on refresh; frames on the account but not on this device show as "1 more frame is on your account" with **Add to this device** (a fresh Google/Apple sign-in for those projects; the directory keeps no names, so the card has none) and Not now; on Home and in the desktop sidebar. (2) **Low-battery notification**, decided with the user: each person chooses per phone, on by default for the owner; read-only watch tokens instead of sessions (above, §15); background check every ~6 h (Android WorkManager, iOS background refresh; phones only), one notification per low spell; permission asked when the owner finishes Connect the frame or turns the switch on; frames on an older backend show "Needs the frame update" until the owner presses Update. Contract 2.1.0. (3) Keyboard: Cmd/Ctrl+A selects all photos, the Mac delete key (Backspace) deletes the selection, Escape closes the viewer, Cmd/Ctrl+V pastes an invite link anywhere on Welcome/Join. (4) Accessibility: checklist rows (setup, connect) say their state to screen readers; text at 200 % checked on the main screens (fixed: Settings' Order row wraps, the frame drawing on Connect doesn't scale). (5) Dark mode checked on the new screens. (6) App icon from the frame mark on every platform (`test/tool/app_icon_test.dart` + flutter_launcher_icons). **Fixed:** the Wi-Fi list never stopped saying "Looking for networks…" (Stream.timeout held back the end of the scan; now a plain timer). `frame_sim sync --battery` and the pretend frame's battery slider let the notification be tried. Not run: the backend suite's new watch-token step needs an empty project, and the user's main account has no spare slot (both used); the routes were checked on the dev project with a temporary member instead.
- 2026-10-04: **Pairing starts by reading `info`, not by an explicit bond.** First try of 3f on an Android phone against `tools/ble_frame` on a Mac: the app's `createBond()` before any read was refused by the Mac at once (SMP pairing failed) and showed "Something went wrong". Now the app reads `info` and lets the encrypted read trigger the OS's pairing (Android, iOS, macOS do this and retry the read); only if the read is refused for lack of pairing does it bond explicitly (Windows, Linux), and a refused bond says "The code didn't match". The pretend frame defaults to no pairing (a Mac can't use the frame's fixed code anyway), and finishes linking even when the phone misses a status. After that the whole flow worked: find → Wi-Fi → linked → first check → the photo shown. docs/pairing.md updated.
- 2026-10-03: **Phase 3f built.** Connect the frame (app-flow §6): get ready → find (scan for the service, auto-pick one frame after 2 s, list several by `InkFrame-XXXX`, give up after 30 s with tips) → pair (the OS asks for the frame's code when `info` is read) → the frame's model and link are checked from `info` ("This frame is a …" with Switch, which clears the photos; "still linked to another Ink Frame") → Wi-Fi from the frame's scan (strongest first, "Other network…", password with show/hide) → finishing checklist from `status` (Joining → Linking → Getting photos) → Done. Expired pairing tokens are replaced silently once; a disconnect after `claimed` counts as done, before it is "Lost the connection". Entry points: setup's end (Connect the frame / Later — add photos first), the frame screen while not connected (owner), Settings → The frame (Connect new hardware, Disconnect). Developer mode adds Connect with a code (token + `frame_sim claim` command, then waits for the claim). **Protocol decided** and written down in docs/pairing.md + `shared/pairing.json` (§9.5 updated): newline-terminated JSON chunked to MTU − 3 for writes and notifications; `info` carries `frame_id` so a frame linked elsewhere is caught before Wi-Fi; `status` gained `syncing`/`ready` and `wifi_failed.reason` so the app can say *why* Wi-Fi failed; the frame keeps no bonds and the app removes the OS bond afterwards; the name goes in the scan response (doesn't fit next to a 128-bit UUID); Android scans in legacy mode (ESP32). `tools/ble_frame` is a pretend frame over real Bluetooth (universal_ble peripheral mode + frame_sim) to try it on a phone before the firmware. **Fixed:** Change model never sent `clear_photos`, so it failed on any frame with photos (`connect_live_test.dart` now covers it with a photo). Not done: pairing with a real frame's static passkey (4b), Windows/macOS passkey pairing (§14). Found while testing: a frame set up (or joined) on one device appears on your other signed-in devices only after signing in again there, because the directory is read at sign-in; reading it again on start/refresh is for 3g.
- 2026-10-03: **Phase 3e built.** Set up a frame (app-flow §1.3): connect Supabase (OAuth through the Worker; PAT in dev mode), model, name, time zone and your name, then a three-row checklist (photo storage, sign-in, signing you in) that saves progress after every step and resumes; the 2-project limit is explained with "Open Supabase"; "Cancel setup" deletes a half-made project. The app ships the backend as assets (`tools/dev/bundle-backend.ts`; a test fails when they're stale) and runs the provisioning in Dart (`Provisioner`, a port of `provision.ts`), verified against the real API by `provision-live-test.ts` (create → owner → app-api answers → delete, ~35 s). Owner tools: Supabase account (connect/reconnect on this device), **Update** (newer schema, or same schema with a different backend fingerprint), **Delete this frame** (typed name), **Wake up** on an asleep frame, **Change** model (warns that the photos go; `PATCH /frame`). Delete my account now deletes the frames you set up. The owner's frame goes on their directory list. Not done: Connect the frame (3f).
- 2026-10-03: **Spike (c): the Supabase OAuth token exchange needs the client secret** (PKCE alone gets `422 Required parameter: client_secret`; with the secret: 24 h access token, refresh works, Management API calls work). The secret can't ship in the app, so the code exchange and refreshes go through a route on the Cloudflare Worker that adds it (stateless, logs nothing); this is the "token-exchange function in `central/`" §3 allowed for. The user registered the OAuth App and asked that owners never have to: confirmed, owners only sign in to their free Supabase account and click Authorize once. Creating projects without the owner's consent is only possible in the developer's own org (Supabase for Platforms), which costs per project and reverses one-project-per-family; not pursued. Details in `docs/spikes/c-supabase-oauth.md`.
- 2026-10-03: **Directory for signing in on a new device.** The user found the link-first sign-in unworkable: someone with no invite and no other device couldn't get back to their frames. Options: the frame list in the user's own Google Drive/iCloud (no central state, but an extra consent and two mechanisms), or a small central directory. The user chose the **directory**, on a free host that doesn't sleep: **Cloudflare Workers + D1** (Supabase free projects pause and take one of the owner's 2 slots; Firebase isn't supported for production on Windows). It stores SHA-256 of `<provider>:<sub>`, frame addresses (not secret) and hashed device tokens, nothing else; `central/` is no longer stateless. The user also asked whether Cloudflare would suit the frame backend better: no. Per family its free storage without a card is about the same as Supabase's, its 10 GB needs a card with uncapped billing, and auth, row security and storage rules would have to be written by hand; it only wins if the developer hosts every family, which reverses the one-project-per-frame decision. Contract `shared/api/directory.yaml`; Worker `central/directory/`.
- 2026-10-03: **Phase 3d built.** Settings (owner edits, others see plain values; side sheet on wide windows), People (invite sheet with QR, share and copy; remove; leave; active invites with revoke), Storage (bar, by person, "getting full" at 80 % and "full" notices on the Frame screen), Account (your name on every frame, "use on another device" QR/link, delete my account), and **Scan QR code** on Join for phones (`mobile_scanner`; `qr_flutter`, `share_plus` added). **Low battery warning** added to the contract and migration 0005 (`low_battery_pct`, 5–50 or null, default 20; changing only it leaves `settings_updated_at` alone). Deleting your account is blocked while you own a frame until frame deletion exists (3e). The time zone list comes from `gen-tz.ts` (zone.tab, 419 zones). Verified: 23 backend test steps and 11 app live tests on a throwaway project; 174 app tests; macOS, Android and iOS builds.
- 2026-10-03: **Sign-in IDs.** Google Cloud project `ink-frame-510506` with Web (main), iOS (also used on macOS), Desktop and Android (debug key; the Play release key's SHA-1 gets added before release) clients; Apple team `48QFANT8RD` with Sign in with Apple on iOS and macOS, and Keychain Sharing on macOS (the Google SDK needs it). The public IDs live in `shared/oauth-clients.json` (tools, wizard) and as defaults in `app_config.dart`; the Desktop secret only in `app/.env.local`. Projects get Google with every ID in one comma-separated `client_id` and **skip nonce check on** (the iOS/macOS Google SDK adds its own nonce, which the app can't pass on), Apple with the bundle ID. The dev project is configured (`tools/dev/auth-providers.ts`). Real sign-ins still to verify per platform (§14).
- 2026-10-02: **Prepare reworked** after the user tried it on desktop (crop wasn't discoverable; Adjust opened behind the photo strip). Now an overview of every photo's frame look (tap one to edit; one photo opens straight in the editor); in the editor the frame-shaped preview is the crop (drag/pinch/scroll, the cut-off parts shown dimmed while moving), "Hold to see original", and Adjust beside or below a canvas that never scrolls away. Adjustments stay per photo with "Use these settings for all photos". Chosen by the user from three options each (app-flow §3.3).
- 2026-09-26: **Phase 3c built.** Frame screen (grid in the panel's calibrated colours by swapping the stored PNG's PLTE before decoding; selection, delete with the member/owner rule; drop files on desktop), Prepare (crop locked to the model's aspect by drag/pinch/scroll, rotate, "On the frame" preview rendered in an isolate, Adjust collapsed), an in-memory upload queue (process in an isolate → request-upload → PUT with progress → finalize; duplicates and a full frame handled), viewer (swipe/arrow keys, delete), and "Change order" as a draggable list. Photos decode through `dart:ui` capped at 2400 px on the long side. Downloads are cached per image id in the app support folder. Live test covers prepare → upload → list → download → delete through the real backend.
- 2026-09-26: **Automatic processing replaces the look presets as the default** (user request: opendithering's Auto-tune, improved where possible; no technical choices shown). opendithering is ported exactly for reference, but measured against the source on 12 photos its Auto-tune was worse than its own untuned preset; Automatic (media-relative mapping with a neutral black, linear-light error diffusion, fidelity-driven per-photo tuning) is 3× closer than Auto-tune and 4× closer than ink-frame-lab's output (§8.3 step 5a). app-flow D2 and §3.3 revised: only crop, rotate and a preview toggle by default; plain-language Adjust collapsed. Open: which Spectra 6 calibration is truest for the E1002 (our presets' EPDOptimize values or opendithering's colorimeter-measured ones); to settle on real hardware in Phase 4.
- 2026-09-26: **Phase 3b done.** `app/lib/imaging/` (pure Dart): the dithering port matches `dithering.js` exactly on 64 golden cases (`tools/golden/gen-vectors.mjs` → `shared/test-vectors/dither.json`; random mode checked statistically), crop/resize (tent filter scaled for downsampling), rotation, looks, pipeline with sha256. PNGs are ~2.4× smaller than ink-frame-lab's exports: minimum bit depth, no filter, and a Dart Zopfli (the user asked for the highest compression). Zopfli's match-chain limit is 1024 rather than 8192: within 0.2 % in size, 3× faster. CI (`.github/workflows/app.yml`) runs the app tests and checks the vectors regenerate unchanged.
- 2026-09-26: **Phase 3a built.** Bundle/application ID `com.psmyles.inkframe` on every platform. Each frame gets its own `SupabaseClient` with the **implicit** auth flow (ID-token and password sign-in never redirect, so PKCE storage isn't needed); sessions are kept in secure storage per project ref and restored at start. On macOS, secure storage uses the legacy keychain so unsigned debug builds work. Dev projects turn on `mailer_autoconfirm` so developer-mode email sign-up works without mail (`provision.ts --keep-email` does it too). Sign-in buttons appear only for configured providers (`--dart-define`, `app/README.md`). `tools/dev/dev-frame.ts` makes a frame on the dev project to join until the wizard exists; `tools/dev/app-live-test.ts` runs the app's data layer against the dev project (6 tests: join, restore, another device, not a member, wrong code, wrong password).
- 2026-09-26: **Phase 2 approved** (`docs/app-flow.md`, D1–D5 and D7–D11 as recommended; layout chosen by window width only, so a narrow desktop window is the phone layout). Its backend additions are done: `frame.synced_manifest_version` (set by `/sync`) and a generated `frame.up_to_date` column, also in the `Frame` schema; and `central/site/` with the `/join` and `/oauth` pages (link parsing tested in `central/tests/`), published to GitHub Pages by `.github/workflows/pages.yml`.
- 2026-09-26: **One Supabase project per frame** (was: one per family, holding many frames). Photos are processed for one panel's resolution and palette, so projects never mix panel types. The person who sets up a frame is its **owner** and hosts it in their free Supabase account (2 active free projects = 2 frames per account). Roles collapse to owner + members; one invite type; the app lists frames across projects. Panel model is chosen at setup; replacement hardware of the same model keeps the photos, a different model needs a model switch that clears them. User-facing words: frame, owner, people, "checks for new photos", "connect the frame", "asleep because it wasn't used for a while"; never space/project/admin/sync. The unreleased migrations 0001–0005 were replaced by a simpler schema (one `frame` row, `members`), and the dev project was reset. Supersedes the space/admin decisions below.
- 2026-09-25: **Phase 1B done** (spike (c) deferred to the start of Phase 3e, as nothing earlier needs the Supabase OAuth App). `tools/frame_sim` (Dart CLI, 8 unit tests against a fake device-api) mirrors the firmware's cache layout and sync rules: downloads go to `cache/tmp` and are checked against sha256 before a rename, the manifest version only advances when every image arrived, `410` wipes the cache and secret, new arrivals are shown first. `tools/dev/sim-scenario.ts` passes the §12.1 scenario with it against the dev project.
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
