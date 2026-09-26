# Ink Frame app: flow and UI structure

> **Status:** APPROVED 2026-09-26 (Phase 2, PLAN.md §11). D1–D5 and D7–D11 accepted as recommended.
> Each section answers a question from PLAN.md §8.5. Details below are defaults that can still change during Phase 3.
> Revised 2026-09-26 for **one Supabase project per frame** (PLAN.md §2, §16).

---

## 0. Decisions for you (summary)

| # | Question | Recommendation |
|---|---|---|
| D1 | Navigation model | **Home = every frame you're on**, whoever set it up. No switcher, no bottom tabs; Account opens from the header. Desktop uses two panes (§2) |
| D2 | Dithering control | **Presets first** ("Balanced", "Smooth", "Crisp", "Grainy"); the full ink-frame-lab controls sit behind "Advanced" (§3.3) |
| D3 | Upload queue | **In memory for v1**, with per-photo retry; a queue that survives an app restart comes later (§3.5) |
| D4 | Invite links | **HTTPS links** via a small page on GitHub Pages that opens the app, since `inkframe://` links aren't clickable in most messengers (§5.1). Needs a `central/` addition |
| D5 | Apple sign-in on Windows/Linux | **Not offered.** Google only, plus email/password in dev mode on dev projects (§7.1) |
| D7 | "Is my frame up to date?" | Record the manifest version the frame last received, so the app can say **"Up to date" / "Changes waiting"** (backend addition, §4.2) |
| D8 | Photo order UI | Offer drag-to-reorder **only when the frame is set to "In order"**; in shuffle it means nothing (§3.6) |
| D9 | Visual direction | Calm, photo-first "gallery" look, paper-white / charcoal, one Spectra-6 accent colour, platform fonts (§8) |
| D10 | Localization | English only in v1, but every string in ARB files from day one (§8.4) |
| D11 | Links carry which key | Use the project's short **publishable key** (`sb_publishable_…`) in invite and "another device" links, so QR codes stay small (§1.4) |

(D6, a "space name", is gone: each frame's own name is what people see.)

### Words used in the app
| Say | Don't say |
|---|---|
| **frame** ("Kitchen") | space, project |
| **owner** / "Set up by Priya" | admin |
| **people** / "Shared with 4 people" | members |
| **Invite someone to add photos** | join a space |
| "**checks for new photos** once a day" / "**last checked** 3 h ago" | sync, manifest |
| **Connect the frame** | pair, claim, provision |
| "**asleep because it wasn't used for a while**" | paused, restore |
| "your free **Supabase account**" (setup only) | backend, database, project |

---

## 1. First run

### 1.1 Welcome
```
┌─────────────────────────────┐
│        [frame illustration]  │
│         Ink Frame            │
│  Your family's photos on     │
│  e-ink frames.               │
│                              │
│  [ I've been invited ]       │  ← primary: most people are invited
│  [ Set up a frame ]          │  ← secondary: the person who owns the frame
│                              │
│  Already use Ink Frame? Sign in │ (new phone: see 1.4)
└─────────────────────────────┘
```

### 1.2 Join a frame (invited)
1. **Get the invite**: one of
   - opened from an invite link (skips this screen),
   - **Scan QR** (mobile),
   - **Paste link** (all platforms; desktop's main path). A bare code isn't enough because the app also needs the frame's address, so the paste box asks for the whole link.
2. **Sign in**: "Continue with Google" / "Continue with Apple" (per platform, §7.1). Copy: *"Your account is only used to recognise you on this frame."* Joining a second frame reuses the same sign-in without asking again.
3. **Your name**: "What should the others see?" For the first frame it's empty (with the Google/Apple first name as a suggestion chip); for later frames it's pre-filled with the name you used before.
4. `POST /invites/accept` → the **Frame** screen, with a one-time tip: *"Add photos with the + button. The frame checks for new photos once a day, or press its green button to check now."*

Errors: invalid/expired/used invite → "This invite has expired or was already used. Ask for a new one." (single message for all, matching the API). Sign-in cancelled → back to step 2, no error.

### 1.3 Set up a frame (owner)
One screen with a **checklist that fills in**, so it's clear what's happening and where it stopped.

```
Set up a frame
 ✓ Connect your free Supabase account     [explainer card]
 ✓ Which frame do you have?               reTerminal E1002 7.3″  (picture of each model)
 ✓ Name it                                Kitchen · Time zone: Europe/Berlin
 ● Getting its photo storage ready…       ~ a few seconds
 ○ Turning on sign-in
 ○ Signing you in
 ○ Connect the frame                      [Connect now]  [Later — add photos first]
```

- **Explainer card** (before connecting): the frame's photos are kept in *your own* free Supabase account; you'll be the frame's owner; one free account can run **2 frames**; nobody else (including us) can see the photos.
- **Connect Supabase** opens the browser (Supabase OAuth, PLAN.md §6.2). Skipped when the owner's account is already connected (their second frame). Dev mode shows "Paste access token" instead.
- **Which frame do you have?**: the list of models with a picture, name and screen size. This fixes the resolution and colours for every photo (PLAN.md §2). Changing it later clears the photos (§4.3).
- **Name and time zone**: name required ("Kitchen", "Grandma's"); time zone defaults to the phone's.
- **Region** isn't asked: suggested from the time zone (`region_selection: smartGroup`), changeable under "More options".
- The storage steps run automatically (measured ~17 s). Each step is **idempotent and resumable**: the ref and progress are saved in secure storage after each step, so closing the app or a failure resumes from the failed step.
- **Failure** shows on the failed row: plain explanation + **Try again**. Special cases:
  - *2-frame limit* → "Your free Supabase account already runs 2 frames. Someone else in the family can set up this one with their own free account, or you can delete one of your frames." + **Open Supabase**.
  - *Browser consent cancelled* → back to step 1.
- **Connect the frame** goes to §6; **Later** lands on the empty Frame screen, where photos can be added before the hardware arrives.

### 1.4 Returning on a new device
The app needs each frame's address to sign in, and only owners can invite. The addresses (project URL + publishable key) aren't secret, so:
- **Account → "Use on another device"** shows a QR and a link holding the addresses of **all** your frames (no invite codes): `…/join#u=<url1>&k=<key1>&u=<url2>&k=<key2>`.
- On the new device, "Already use Ink Frame? Sign in" = scan or paste that (or any invite link) → sign in once → every frame where you're still a member appears. A frame you've since been removed from is skipped with a note.
- An owner on a new device also reconnects Supabase from the frame's settings (§4.4) to regain owner tools.

---

## 2. Navigation

### 2.1 Map
```
Welcome ─┬─ Invited → Join ───┐
         └─ Set up a frame ───┤
                              ▼
Home (every frame you're on)
 ├─ Frame
 │   ├─ Photo viewer (swipe; info; delete)
 │   ├─ Add photos → Prepare (crop/preview/adjust) → Upload
 │   ├─ Settings (owner edits; others read)
 │   ├─ People (invite, remove, leave)
 │   └─ Storage
 ├─ Set up a frame (wizard, §1.3)
 ├─ Join a frame (paste/scan an invite)
 └─ Account: your name, use on another device, sign out, delete account, about, dev mode
```

### 2.2 Mobile
- **Home** is a list of frame cards; each shows "Set up by Priya" when it isn't yours. Header: app name and an **avatar** button (→ Account). A "+" button offers **Set up a frame** / **Join with an invite**.
- Drill-down navigation with a back button; **no bottom tabs** (D1).
- On a Frame screen, **"+"** = Add photos; the header has Settings (⚙) and People (👥).

### 2.3 Desktop (Windows first; macOS/Linux same)
```
┌───────────────┬────────────────────────────────────────────────┐
│ Ink Frame     │  Kitchen                       ⚙  👥  [+ Add photos]│
│               │  Up to date · last checked 3 h ago · 🔋 80%      │
│ FRAMES        │ ┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐            │
│ ▸ Kitchen     │ │    ││    ││    ││    ││    ││    │            │
│   Grandma's   │ └────┘└────┘└────┘└────┘└────┘└────┘            │
│   (set up by  │  … photo grid, drop files anywhere to add …     │
│    Priya)     │                                                  │
│ + Set up / join│                                                 │
│ Account       │                                                  │
└───────────────┴────────────────────────────────────────────────┘
```
- **Two panes** from ~900 px wide: sidebar (frames, set up / join, Account) and detail. Below that width, the mobile layout.
- **One app, one set of screens.** The layout is chosen by **window width only**, never by platform, so narrowing the desktop window shows exactly the phone layout (and widening a tablet shows two panes). Gestures work with both touch and mouse everywhere (long-press also works with a mouse; hover is an extra, never the only way). What width can't change is the platform plumbing: sign-in sheets, the photo library picker, the QR camera, the share sheet and Bluetooth, each of which has a desktop path (§6.3, §7.1).
- **Drag and drop** files onto the window (or onto a frame in the sidebar) → Prepare.
- Keyboard: Delete removes selected photos (with confirm), Ctrl/Cmd+A selects all, arrows move in the viewer, Ctrl/Cmd+V pastes an invite link anywhere on Welcome/Join.
- Prepare (the editor) opens **full window**; settings, people and storage open as **side sheets**.

---

## 3. Photos

### 3.1 Frame screen (photo grid)
- Grid of photos **in the order the frame uses** (by position). Tiles show the e-ink preview colours. A small initial in the corner; long-press (mobile) / hover (desktop) shows "Added by Alice · 3 days ago". Deleted accounts show "Someone who left".
- **Header status** (§4.2).
- **Selection**: long-press (mobile) or checkbox on hover / Shift-click (desktop) → action bar: **Delete** (only if every selected photo is yours or you're the owner; otherwise the button explains why).
- **Empty state**: "No photos yet. Add some and the frame will show them after it next checks." + Add photos.

### 3.2 Add photos: pick
- Mobile: `image_picker` multi-select. Desktop: file dialog or drag-drop. Formats: JPEG, PNG, WebP, HEIC (iOS/macOS only).
- The target is the frame you're on. (Sending one photo to several frames, processed for each frame's model: later.)

### 3.3 Prepare (crop, preview, adjust)
```
┌──────────────────────────────────────────┐
│ ✕  Prepare 5 photos                [Upload 5]│
│ ┌──────────────────────────────────────┐ │
│ │   crop box locked to 800×480 (5:3)   │ │  pinch/drag or mouse wheel/drag
│ │                                      │ │
│ └──────────────────────────────────────┘ │
│  [ Original | On the frame ]             │  toggle: shows the dithered preview
│  Look:  (Balanced) Smooth  Crisp  Grainy │  presets (D2)
│         Advanced ▸                        │
│ ┌──┐┌──┐┌──┐┌──┐┌──┐                     │  strip of picked photos; ✕ removes one
│ └──┘└──┘└──┘└──┘└──┘                     │
└──────────────────────────────────────────┘
```
- **Crop**: aspect locked to the frame's model; defaults to centre crop (as `getCroppedCanvas()`); rotation in 90° steps.
- **Preview**: "On the frame" shows the dithered result in the calibrated `color` values. Rendering runs in an isolate and updates ~300 ms after the crop stops moving.
- **Presets** (D2), all from ink-frame-lab's options:
  - *Balanced* (default): Floyd–Steinberg, serpentine
  - *Smooth*: Jarvis, serpentine
  - *Crisp*: Atkinson
  - *Grainy*: random (luma)
- **Advanced** (collapsible): algorithm (error diffusion / ordered / random / none), kernel (all 9), serpentine, Bayer size, random type. "Apply to all photos" button.
- The last-used look is remembered per frame model.
- **Upload N** starts the queue and returns to the Frame screen.

### 3.4 Processing and upload
Per photo: crop → resize → dither → indexed PNG → sha256 → `request-upload` → PUT → `finalize` (PLAN.md §8.3). The grid shows **placeholder tiles with progress** at the end of the grid.

### 3.5 Upload errors (D3)
- Failed tiles show **Retry** / **Remove**. "Retry all" in a banner when several fail.
- *Already on this frame* (409): the tile disappears with a toast "1 photo was already on the frame".
- *Storage full* (quota): stop the queue; banner "Kitchen's storage is full. Delete some photos to add more." (§5.3).
- Mobile: if the app goes to the background mid-queue, it keeps going while the OS allows; on return, unfinished items show Retry.

### 3.6 Order and viewer
- **Reorder** (owner only, D8): when the frame is set to "In order", the grid gets drag handles. Each drop = one `POST /images/reorder`. In "Shuffle" the grid shows by date added and there's no reorder.
- **Viewer**: tap a tile → full-width preview, swipe between photos, info line, Delete. **No re-editing**: only the processed PNG is stored, so to change a crop you delete and add again (the viewer says so).

---

## 4. The frame

### 4.1 Home: frame cards
Card = latest photo as the cover, name, "Set up by …" when it isn't yours, and one status line: "Up to date · last checked 3 h ago" / "Changes waiting · next check around 18:00" / "⚠ Hasn't checked in for 3 days" / "Not connected yet". Empty Home: "No frames yet" + **Set up a frame** and **I've been invited**.

### 4.2 Status and "when will it change?" (D7)
- **Up to date** when the frame has received the latest changes; otherwise **"Changes waiting"**.
- **Next check**: `last_seen_at + sync_interval_s` shown as a time.
- **Always-visible hint** under the status: *"To show changes now, press the green button on the frame."*
- **Warnings**: not seen for more than 2× the check interval → "Hasn't checked in since Tuesday. Check the frame's Wi-Fi and battery." Battery < 20 % → "Battery low (15 %)". No hardware → "Not connected yet" + **Connect the frame** (owner).
- The Frame screen header shows the same plus battery and signal.

### 4.3 Settings (owner edits; others see them read-only)
| Setting | Control | Values |
|---|---|---|
| Name | text | 1–40 chars |
| Change photo every | picker | 1 h, 2 h, **4 h**, 8 h, 12 h, 1 day, 2 days |
| Order | segmented | **Shuffle** / In order |
| Quiet hours | toggle + two time pickers | e.g. 22:00–07:00; "The frame won't change photos during these hours" |
| Time zone | searchable list | defaults to the owner's phone; shown as "Europe/Berlin (CET)" |
| Check for new photos | picker | 1 h … 2 days, **1 day**; hint: "More often uses more battery" |
| Frame model | read-only row + "Change" | changing warns "All N photos will be removed, because they were made for the <old> screen", then clears them |
| Hardware | status + actions | "Connected · reTerminal E1002 · firmware 1.0.2" · **Connect new hardware** (same model keeps the photos) · **Disconnect** (the frame wipes itself at its next check) |

Each change saves immediately (`PATCH`) with a small "Saved · the frame gets it at its next check".

### 4.4 Owner tools (bottom of Settings, owner only)
- **Supabase account**: connected / **Reconnect** (after a reinstall or on a new device).
- **Update**: shown when the app has a newer backend than this frame ("An update for Kitchen is ready · a few seconds").
- **Delete this frame**: typed confirmation of the name; explains that all photos and everyone's access go, the frame's storage in your Supabase account is deleted, and the hardware keeps its last photos until reset. Uses the Management API (`DELETE /v1/projects/{ref}`).

---

## 5. People

### 5.1 Invites (D4)
- **Frame → People → Invite someone to add photos** (owner): a sheet with a **QR code**, **Share link** (system share sheet), **Copy link**, and **Copy code**. Options (collapsed): "Link works for 1 person / up to 10 people", "Expires in 1 day / **7 days** / 30 days".
- **Link format**: `https://<pages-domain>/join#u=<project_url>&k=<publishable_key>&c=<code>`. The page shows "Open in Ink Frame", store badges, and the code as text. Everything after `#` never reaches the server. The app registers `inkframe://join?...` too; the page redirects to it.
- **Active invites** list under the people, with **Revoke** (owner).

### 5.2 People list
- Each person: name, "Owner" badge on the one who set it up, "You". The owner can **Remove** someone (confirm: "Their photos stay; you can delete them"); anyone else can **Leave this frame**.

### 5.3 Storage
- Frame → Storage: a bar "**312 MB of 1 GB** (free Supabase plan)", then per-person breakdown (the owner sees everyone; others see themselves). A note that the frame's downloads aren't counted here.
- Banner on the Frame screen at **80 %** ("Storage is getting full") and at the limit (uploads blocked, §3.5).
- **Quota values** (PLAN.md §15): recommend only the frame limit (≈ 90 % of 1 GB) in v1, no per-person limits.

---

## 6. Connect the frame (Bluetooth)

Reached from setup (§1.3), from "Not connected yet", or from Settings → Hardware → Connect new hardware. Owner only.

### 6.1 Steps
1. **Get ready**: illustration: "Hold the frame's green button for 3 seconds until it shows a 6-digit code." (First-time frames show it on power-up.)
2. **Find**: scan for `InkFrame-XXXX`. One found → auto-select; several → list with the XXXX suffix matching the frame's screen.
3. **Connect**: the OS pairing prompt asks for the code shown on the frame.
4. **Wi-Fi**: networks the frame can see (from `wifi_scan`), strongest first; pick one, enter the password (show/hide). Note: *"The frame needs a 2.4 GHz network."* "Other network…" for hidden SSIDs.
5. **Finishing**: a checklist driven by `status` notifications: Joining Wi-Fi → Linking to Kitchen → Getting photos → **Done**. The frame's screen shows its first photo, or "Ready. Add photos in the Ink Frame app."

The pairing token is requested just before step 5 and re-requested automatically if it has expired.

### 6.2 Errors
| Case | What the user sees |
|---|---|
| Bluetooth off | "Turn on Bluetooth" + button to settings |
| Permission denied | explanation + "Open settings" |
| No frame found (30 s) | tips: is the code showing? move closer; hold the green button again. Retry |
| Wrong code | "The code didn't match. Check the frame's screen and try again." (back to step 3) |
| Wi-Fi failed | "Couldn't join <SSID>." Likely causes: wrong password, 5 GHz network, too far. Back to step 4 |
| Token expired | handled silently (new token, retry) |
| Different model (`model_mismatch`) | "This is a Pimoroni Inky 7.3″, but Kitchen is set up for a reTerminal E1002. Switch Kitchen to the Inky? Its N photos will be removed." → Switch (clears, retries) / Cancel |
| Hardware linked to another frame | "This frame is still linked to another Ink Frame. Hold its green button for 10 seconds to reset it, then start again." |
| Connection lost mid-way | "Lost the connection to the frame." Retry from step 2 |

### 6.3 Without Bluetooth (desktop testing, dev mode)
"Connect the frame" offers **Connect with a code (developer)**: shows a pairing token to paste into `frame_sim claim`. The frame shows as connected after its first check.

---

## 7. Accounts and platforms

### 7.1 Sign-in per platform (D5)
| Platform | Offered |
|---|---|
| iOS, macOS | Apple, Google |
| Android | Google |
| Windows, Linux | Google (browser, loopback) |
| Any, dev mode + dev project | + email/password |

Consequence to accept: someone who joined with **Apple** on an iPhone can't sign in on Android/Windows with that account in v1; they'd join again with Google (a second person on the frame). Copy on the iOS sign-in screen: "Use Google if you also want to use Ink Frame on Android or a computer."

### 7.2 Account screen
- **Your name** (edit): applies to every frame you're on (the app updates each).
- **Use on another device** (§1.4).
- **Sign out**.
- **Delete my account**: lists your frames. For frames set up by others: you leave, with an "Also delete my photos" checkbox. For frames you own: they are **deleted** (shown by name, with the §4.4 warning). One typed confirmation for the lot.
- About/licences; **Developer** (dev mode toggle via 7 taps on the version).

---

## 8. Look and feel (D9)

### 8.1 Direction
Photo-first and quiet, like a printed album: large photos, few borders, generous spacing. The interface steps back so the family's pictures carry the colour.

### 8.2 Theme
- Material 3, custom colour scheme. **Light**: warm paper white (#F7F5F0) surfaces, near-black text. **Dark**: charcoal (#141414) surfaces. Follows the system setting, with an override in Account.
- **One accent**: a red taken from the Spectra 6 palette (tuned for contrast) for primary actions. Status colours (the "Up to date" green, warning amber) also come from that palette, muted.
- **Type**: platform fonts (SF on Apple, Roboto on Android, Segoe UI on Windows). Headline sizes kept modest.
- Motion: short fades and shared-element transitions from grid tile to viewer; respects "reduce motion".

### 8.3 Accessibility
- 48 dp touch targets; text scales to 200 % without clipping (the grid drops columns).
- Semantics labels on photo tiles ("Photo added by Alice on 12 March"), status lines, and progress steps.
- Contrast AA in both themes; state never shown by colour alone (icons + text).
- Full keyboard navigation on desktop.

### 8.4 Localization (D10)
English only in v1. All strings in ARB files via `flutter_localizations`/`intl` from the start; dates and times formatted by locale.

---

## 9. Backend changes this draft needed (done 2026-09-26)

| Change | Why | Size |
|---|---|---|
| `frame.synced_manifest_version`, set by `/sync` to the version it returned, and a generated `frame.up_to_date` (also in the `Frame` schema) that is also false while settings are waiting | D7: "Up to date / Changes waiting" | ✅ migrations 0001/0004 |
| `central/` GitHub Pages: `/join` page (invite and "another device" links) and `/oauth` bounce page (Supabase OAuth on mobile) | D4 and PLAN.md §6.1 | ✅ `central/site/` (see `central/README.md`) |

Both go through the contract first (CLAUDE.md rule).

---

## 10. Screen inventory and states

| Screen | Loading | Empty | Error |
|---|---|---|---|
| Welcome | – | – | – |
| Join (invite, sign-in, name) | spinner on buttons | – | invalid invite; sign-in failed; network |
| Set up a frame | per-step spinner | – | per-step error + retry; 2-frame limit; consent cancelled |
| Home | skeleton cards | "No frames yet" | offline banner; per-card asleep / not checked in |
| Frame (grid) | skeleton tiles | "No photos yet" | load failed + retry; removed from the frame → back to Home with a note |
| Photo viewer | progressive image | – | image failed to load |
| Prepare | preview spinner | – | unreadable file ("Couldn't open this photo") |
| Upload queue | progress tiles | – | per-tile retry; storage full; duplicate toast |
| Settings | skeleton rows | – | save failed (field reverts, toast) |
| People / invites | skeleton | "Just you so far" + Invite | – |
| Storage | skeleton | – | – |
| Connect the frame | per-step | – | §6.2 table |
| Account | – | – | delete failed (per frame, retry) |

**Per-frame states** shown as a banner on the Frame screen and a badge on its Home card:
- **Asleep** (any API returns HTTP 540): owner → "Kitchen's photo storage is asleep because it wasn't used for a while. **Wake it up** (about 3 minutes)." with progress; others → "Kitchen is asleep because it wasn't used for a while. Ask Priya to open Ink Frame to wake it up." The frame keeps showing its photos meanwhile.
- **Update ready** (owner, bundled backend newer): "An update for Kitchen is ready. **Update** (a few seconds)."
- **App too old** (backend newer than the app knows): "Update Ink Frame to keep using Kitchen."

---

## 11. Components

`FrameCard`, `StatusLine` (+ `CheckHint`), `PhotoTile` (states: ready / uploading with progress / failed), `PhotoGrid` (selection, reorder), `CropEditor`, `EinkPreview`, `LookPresets` + `DitherAdvanced`, `UploadBanner`, `ModelPicker`, `ChecklistProgress` (setup, connect, wake up), `InviteSheet` (QR, share, copy), `PersonRow`, `UsageBar`, `SettingRow` variants (picker, segmented, toggle, time range, time zone search), `Banner` (asleep / update / storage / offline), `EmptyState`, `ErrorState`, `ConfirmDialog` (incl. typed confirmation), `SidebarLayout` (desktop two-pane).

---

## 12. Packages (final list for Phase 3)

| Package | Use |
|---|---|
| `supabase_flutter` | auth sessions (one client per frame), PostgREST reads, Storage signed URLs |
| `flutter_riverpod` | state |
| `go_router` | navigation, deep links |
| `google_sign_in` | Google on iOS/Android/macOS |
| `sign_in_with_apple` | Apple on iOS/macOS |
| `flutter_web_auth_2` | **new**: browser flows: Supabase OAuth (all platforms) and Google loopback on Windows/Linux |
| `universal_ble` | Bluetooth |
| `image_picker`, `file_selector`, `desktop_drop` | photo input |
| `mobile_scanner` | QR scan |
| `qr_flutter` | **new**: show invite QR |
| `share_plus` | **new**: share invite links |
| `app_links` | `inkframe://` links |
| `url_launcher` | open Supabase dashboard, help pages |
| `flutter_secure_storage` | platform token, sessions, setup progress |
| `cached_network_image` | grid thumbnails (cache key = image id, since signed URLs change) |
| `crypto` | sha256 |
| `flutter_timezone` | **new**: device IANA time zone for new frames |
| `path_provider` | temp files for processing |
| `flutter_localizations`, `intl` | strings, date formats |

Not needed: an image-cropping package (the crop editor is a locked-aspect `InteractiveViewer`), `package:image` outside tests, `permission_handler` (`universal_ble` and the pickers request their own permissions; revisit if Android 12+ BLE permissions need it).

---

## 13. Phase 3 milestones (refined)

| # | Scope | Done when |
|---|---|---|
| **3a** | Scaffold (iOS, Android, Windows, macOS), theme, routing, dev mode, data layer with **one Supabase client per frame**; **Join** with a pasted link; Google sign-in (mobile + Windows loopback), Apple on iOS/macOS; Home listing frames across projects (read-only) | Join the dev frame on Windows and a phone, see it on Home |
| **3b** | `lib/imaging/` port, indexed PNG encoder, golden tests (PLAN.md §8.3–8.4) | Golden parity passes in CI |
| **3c** | Frame screen, Prepare (crop/preview/presets/advanced), upload queue, viewer, delete, reorder | §12.2 steps 3–5 on Windows |
| **3d** | Settings, invites (sheet, `/join` page), people, storage, account (name, another device, delete account) | Phone joins by QR; usage matches `GET /usage` |
| **3e** | **Spike (c)** first; Set up a frame (wizard incl. model picker), owner tools (update, wake up, delete frame, change model), `central/` OAuth bounce page | §12.2 step 1 on Windows with a fresh project |
| **3f** | Connect the frame over Bluetooth, replacement hardware, disconnect (+ dev "connect with a code") | Connect `frame_sim` by code; BLE against a stub or the first firmware build |
| **3g** | Polish: empty/error state audit, accessibility pass, dark mode, desktop keyboard shortcuts, store assets prep | §12.2 passes on Windows and one phone |
