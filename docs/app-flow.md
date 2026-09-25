# Ink Frame app: flow and UI structure

> **Status:** DRAFT for approval (Phase 2, PLAN.md §11). Nothing here is built yet.
> Each section answers a question from PLAN.md §8.5 with a recommendation. Items marked **Decide** need your yes/no; everything else is a default you can change.

---

## 0. Decisions for you (summary)

| # | Question | Recommendation |
|---|---|---|
| D1 | Navigation model | **One home screen: the frame list.** Space and Account screens open from the header, with no bottom tabs. Desktop uses two panes (§2) |
| D2 | Dithering control | **Presets first** ("Balanced", "Smooth", "Crisp", "Grainy"); the full ink-frame-lab controls sit behind "Advanced" (§3.3) |
| D3 | Upload queue | **In memory for v1**, with per-photo retry; a queue that survives an app restart comes later (§3.5) |
| D4 | Invite links | **HTTPS links** via a small page on GitHub Pages that opens the app, since `inkframe://` links aren't clickable in most messengers (§5.1). Needs a backend/central addition |
| D5 | Apple sign-in on Windows/Linux | **Not offered.** Google only, plus email/password in dev mode on dev projects (§7.1) |
| D6 | Space name | Add a **space name** that every member sees (needs a small backend addition, §9) |
| D7 | "Is my frame up to date?" | Record the manifest version each frame last received, so the app can say **"Up to date" / "N changes waiting"** (backend addition, §4.2) |
| D8 | Photo order UI | Offer drag-to-reorder **only when the frame is set to "In order"**; in shuffle it means nothing (§3.6) |
| D9 | Visual direction | Calm, photo-first "gallery" look, paper-white / charcoal, one Spectra-6 accent colour, platform fonts (§8) |
| D10 | Localization | English only in v1, but every string in ARB files from day one (§8.4) |

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
│  [ Join a family space ]     │  ← primary: most people are invited
│  [ Set up a new space ]      │  ← secondary: the one admin
│                              │
│  Already have a space? Sign in│  (reinstall / new phone: see 1.4)
└─────────────────────────────┘
```

### 1.2 Join a family space
1. **Get the invite**: one of
   - opened from an invite link (skips this screen),
   - **Scan QR** (mobile),
   - **Paste link** (all platforms; desktop's main path). A bare code isn't enough because the app also needs the space's address, so the paste box asks for the whole link.
2. **Sign in**: "Continue with Google" / "Continue with Apple" (per platform, §7.1). Copy: *"Your account is only used to recognise you in this family space."*
3. **Your name**: "What should your family see?" Pre-filled with the first name from the Google/Apple profile *as a suggestion only* (the plan says it's typed, not taken; the user confirms or edits it).
4. `POST /invites/accept` → lands on **Home**, scrolled to the frame the invite was for (if any), with a one-time tip: *"Add photos with the + button. They reach the frame at its next sync."*

Errors: invalid/expired/used invite → "This invite has expired or was already used. Ask for a new one." (single message for all, matching the API). Sign-in cancelled → back to step 2, no error.

### 1.3 Set up a new family space (admin wizard)
One screen with a **checklist that fills in**, so it's clear what's happening and where it stopped.

```
Set up your family space
 ✓ Connect your Supabase account        [explainer: free, photos stay in your account]
 ✓ Choose where to keep your photos     Region: Asia-Pacific (suggested from your time zone)
 ● Creating your space…                  ~ a few seconds
 ○ Setting up the database
 ○ Installing the server functions
 ○ Turning on sign-in
 ○ Signing you in and naming the space
```

- **Before step 1**, an explainer card: what Supabase is, that it's free, that the family's photos live in *their* account, the 2-free-project limit, and that they are the space's **admin**.
- **Connect Supabase** opens the browser (Supabase OAuth, §6.2). Dev mode shows "Paste access token" instead.
- **Organisation**: skipped when there is one; a picker when several.
- **Region**: a short list of friendly names ("Europe", "Americas", "Asia-Pacific", or a specific city in "More…"), suggested from the device time zone. Uses `region_selection: smartGroup` unless a specific one is picked.
- **Space name**: "Singh family" etc. (D6).
- Steps 3–6 run automatically (measured ~17 s total). Each step is **idempotent and resumable**: the ref and progress are saved in secure storage after each step, so closing the app or a failure resumes from the failed step.
- **Failure** shows on the failed row: plain explanation + **Try again**. Special cases:
  - *2-project limit* → "Your Supabase account already has 2 active free projects. Pause or delete one at supabase.com, then try again." + **Open Supabase** button.
  - *Browser consent cancelled* → back to step 1.
- **Finish**: sign in with Google/Apple → name → Home with an empty state that leads to **Add your first frame**.

### 1.4 Returning on a new device
The app also needs the space's address to sign in, and ordinary members can't create invites. But the address (project URL + public key) isn't secret, so:
- **Account → "Use on another device"** shows a QR and a link with the address only (no invite code), on any device already signed in.
- On the new device, "Already have a space? Sign in" = scan or paste that (or any invite link) → sign in → existing members land on Home. Someone who isn't a member yet sees "You're not in this family space yet. Ask for an invite."
- The admin on a new device also reconnects Supabase from Space → Admin.

---

## 2. Navigation

### 2.1 Map
```
Welcome ─┬─ Join ─────────────┐
         └─ Set up (wizard) ──┤
                              ▼
Home (frames in the current space)                 [space switcher when >1 space]
 ├─ Frame
 │   ├─ Photo viewer (swipe; info; delete)
 │   ├─ Add photos → Prepare (crop/preview/adjust) → Upload
 │   ├─ Frame settings
 │   └─ Frame members & invites
 ├─ Add frame (Bluetooth flow, §6)
 ├─ Space
 │   ├─ Members & space invites
 │   ├─ Storage (usage)
 │   └─ Admin (admin only): Supabase connection, update, restore, rename, delete space
 └─ Account: display name, spaces list (add/leave), sign out, delete account, about, dev mode
```

### 2.2 Mobile
- **Home** is a list of frame cards. The header shows the **space name** (tap → space switcher sheet when there's more than one) and an **avatar** button (→ Account). A **Space** entry sits in the header overflow or as a row under the frames ("Family: 4 members · 312 MB used").
- Drill-down navigation with a back button; **no bottom tabs** (D1): there are only three destinations and the frame is where people spend their time.
- **FAB "+"** on a Frame screen = Add photos. On Home, "+" = Add frame.

### 2.3 Desktop (Windows first; macOS/Linux same)
```
┌───────────────┬────────────────────────────────────────────────┐
│ Singh family ▾│  Kitchen                       ⚙  👥  [+ Add photos]│
│               │  Up to date · synced 3 h ago · 🔋 80%            │
│ FRAMES        │ ┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐            │
│ ▸ Kitchen     │ │    ││    ││    ││    ││    ││    │            │
│   Living room │ └────┘└────┘└────┘└────┘└────┘└────┘            │
│   + Add frame │  … photo grid, drop files anywhere to add …     │
│               │                                                  │
│ Space         │                                                  │
│ Account       │                                                  │
└───────────────┴────────────────────────────────────────────────┘
```
- **Two panes** from ~900 px wide: sidebar (space switcher, frames, Space, Account) and detail. Below that width, the mobile layout.
- **Drag and drop** files onto the window (or a frame in the sidebar) → Prepare.
- Keyboard: Delete removes selected photos (with confirm), Ctrl/Cmd+A selects all, arrows move in the viewer, Ctrl/Cmd+V pastes an invite link anywhere on Welcome/Join.
- Prepare (the editor) opens **full window**; settings and members open as **side sheets** over the detail pane.

---

## 3. Photos

### 3.1 Frame screen (photo grid)
- Grid of photos **in the order the frame uses** (by position). Tiles show the e-ink preview colours. A small uploader avatar/initial in the corner; long-press (mobile) / hover (desktop) shows "Added by Alice · 3 days ago". Deleted accounts show "Former member".
- **Header status** (§4.2).
- **Selection**: long-press (mobile) or checkbox on hover / Shift-click (desktop) → action bar: **Delete** (only if every selected photo is yours or you own the frame; otherwise the button explains why).
- **Empty state**: "No photos yet. Add some and they'll appear on the frame at its next sync." + Add photos.

### 3.2 Add photos: pick
- Mobile: `image_picker` multi-select. Desktop: file dialog or drag-drop. Formats: JPEG, PNG, WebP, HEIC (iOS/macOS only).
- The target frame is the one you're on. (Sending one photo to several frames at once: later.)

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
- **Crop**: aspect locked to the frame model; defaults to centre crop (as `getCroppedCanvas()`); rotation in 90° steps.
- **Preview**: "On the frame" shows the dithered result in the calibrated `color` values. Rendering runs in an isolate and updates ~300 ms after the crop stops moving; a small spinner shows while it works.
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
- *Storage full* (quota): stop the queue; banner "Your space is out of storage. Delete some photos to add more." (§5.3).
- Mobile: if the app goes to the background mid-queue, it keeps going while the OS allows; on return, unfinished items show Retry. (A queue that survives the app being killed is later.)

### 3.6 Order and viewer
- **Reorder** (owner only, D8): when the frame is set to "In order", the grid gets drag handles (mobile: long-press-drag; desktop: drag). Each drop = one `POST /images/reorder`. In "Shuffle" the grid shows by date added and there's no reorder.
- **Viewer**: tap a tile → full-width preview, swipe between photos, info line, Delete. **No re-editing**: only the processed PNG is stored, so to change a crop you delete and add again (the viewer says so).

---

## 4. Frames

### 4.1 Home: frame cards
Card = latest photo as the cover, name, and one status line: "Up to date · synced 3 h ago" / "2 changes waiting · next sync around 18:00" / "⚠ Hasn't synced for 3 days". Empty Home: "No frames yet" + **Add frame** (and for joiners without a frame invite: "Ask a family member to invite you to their frame").

### 4.2 Status and "when will it change?" (D7)
- **Up to date** when the frame's last received manifest version equals the current one; otherwise **"N changes waiting"** (count of adds/deletes since then is approximated by "changes").
- **Next sync**: `last_seen_at + sync_interval_s` shown as a time.
- **Always-visible hint** under the status: *"To update now, press the green button on the frame."*
- **Warnings**: not seen for more than 2× the sync interval → "Hasn't synced since Tuesday. Check the frame's Wi-Fi and battery." Battery < 20 % → "Battery low (15 %)".
- Frame screen header shows the same plus battery and signal.

### 4.3 Frame settings (owner; others see them read-only)
| Setting | Control | Values |
|---|---|---|
| Name | text | 1–40 chars |
| Change photo every | picker | 1 h, 2 h, **4 h**, 8 h, 12 h, 1 day, 2 days |
| Order | segmented | **Shuffle** / In order |
| Quiet hours | toggle + two time pickers | e.g. 22:00–07:00; "The frame won't change photos during these hours" |
| Time zone | searchable list | defaults to the phone's; shown as "Europe/Berlin (CET)" |
| Check for new photos | picker | 1 h … 2 days, **1 day**; hint: "More often uses more battery" |
| Remove frame | danger button | typed confirmation of the frame name; explains the frame wipes itself at its next sync |

Each change saves immediately (`PATCH`) with a small "Saved · applies at the next sync".

---

## 5. People

### 5.1 Invites (D4)
- **Frame screen → Members → Invite**: a sheet with a **QR code**, **Share link** (system share sheet), **Copy link**, and **Copy code**. Options (collapsed): "Link works for 1 person / up to 10 people", "Expires in 1 day / **7 days** / 30 days".
- **Space → Members → Invite to space** (admin only): same sheet, space-only membership.
- **Link format**: `https://<pages-domain>/join#u=<project_url>&k=<public_key>&c=<code>`. The page shows "Open in Ink Frame", store badges, and the code as text. Everything after `#` never reaches the server. The app registers `inkframe://join?...` too; the page redirects to it. (Later: universal links / app links on the same domain so the page is skipped.)
- **Active invites** list under the members, with **Revoke**.

### 5.2 Members
- **Frame members**: name, "Owner" badge, "You"; the owner can remove members; anyone can **Leave this frame**.
- **Space members**: name, "Admin" badge, which frames they're on; the admin can **Remove from space** (confirm explains: their frames pass to you, their photos stay).

### 5.3 Storage (usage)
- Space → Storage: a bar "**312 MB of 1 GB** (free Supabase plan)", then per-frame and per-person breakdown (admin sees everyone; members see themselves). A note that the frame's downloads (egress) aren't shown.
- Banner on Home for everyone at **80 %** ("Storage is getting full") and at the limit (uploads blocked, §3.5).
- **Quota values** (PLAN.md §15): recommend only the project limit (≈ 90 % of 1 GB) in v1, no per-frame/per-person limits.

---

## 6. Add a frame (Bluetooth)

### 6.1 Steps
1. **Get ready**: illustration: "Hold the frame's green button for 3 seconds until it shows a 6-digit code." (First-time frames show it on power-up.)
2. **Find**: scan for `InkFrame-XXXX`. One found → auto-select; several → list with the XXXX suffix matching the frame's screen.
3. **Pair**: the OS pairing prompt asks for the code shown on the frame.
4. **Wi-Fi**: networks the frame can see (from `wifi_scan`), strongest first; pick one, enter the password (show/hide). Note: *"The frame needs a 2.4 GHz network."* "Other network…" for hidden SSIDs.
5. **Name**: "Kitchen", "Grandma's" … (time zone taken from the phone).
6. **Connecting**: a checklist driven by `status` notifications: Connecting to Wi-Fi → Registering the frame → Downloading photos → **Done**. The frame screen shows "Ready. Add photos in the Ink Frame app."

The pairing token is requested at step 5 and re-requested automatically if the flow took longer than 10 minutes.

### 6.2 Errors
| Case | What the user sees |
|---|---|
| Bluetooth off | "Turn on Bluetooth" + button to settings |
| Permission denied | explanation + "Open settings" |
| No frame found (30 s) | tips: is the code showing? move closer; hold the green button again. Retry |
| Wrong code | "The code didn't match. Check the frame's screen and try again." (back to step 3) |
| Wi-Fi failed | "Couldn't join <SSID>." Likely causes: wrong password, 5 GHz network, too far. Back to step 4 |
| Claim: token expired | handled silently (new token, retry) |
| Claim: frame belongs to someone else in this space | "This frame is set up by <owner> in this family. Ask them to remove it first." |
| Frame from another space | "This frame is linked to another family space. Hold its green button for 10 seconds to reset it, then start again." |
| Connection lost mid-way | "Lost the connection to the frame." Retry from step 2 |

### 6.3 Without Bluetooth (desktop testing, dev mode)
"Add frame" offers **Pair with a code (developer)**: shows a pairing token to paste into `frame_sim claim`. The frame then appears after its first sync.

---

## 7. Accounts and platforms

### 7.1 Sign-in per platform (D5)
| Platform | Offered |
|---|---|
| iOS, macOS | Apple, Google |
| Android | Google |
| Windows, Linux | Google (browser, loopback) |
| Any, dev mode + dev project | + email/password |

Consequence to accept: someone who joined with **Apple** on an iPhone can't sign in on Android/Windows with that account in v1; they'd join again with Google (a second member). Copy on the sign-in screen for iOS: "Use Google if you also want to use Ink Frame on Android or a computer."

### 7.2 Account screen
Display name (edit), **Spaces** (list, add by invite, leave), sign out, **Delete account** (per space: the "Also delete my photos" checkbox; admin gets the full warning from PLAN.md §15 and the option to delete the whole space instead), About/licences, **Developer** (dev mode toggle via 7 taps on the version, like Android).

### 7.3 Multiple spaces
Space switcher lists each space with its name and your role. Each keeps its own session. Push notifications: none in v1.

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

## 9. Backend changes this draft needs (if approved)

| Change | Why | Size |
|---|---|---|
| `public.space` (one row: `name`) + `PATCH /app-api/space {name}` (admin); set by the wizard | D6: members see the space name | migration + 1 endpoint |
| `frames.synced_manifest_version`, set by `/sync` to the version it returned | D7: "Up to date / N changes waiting" | migration, 1 line in `svc_sync_frame` |
| `central/` GitHub Pages: `/join` page (invite links) and `/oauth` bounce page (Supabase OAuth on mobile) | D4 and §6.1 of the plan | two static pages |

All three go through the contract first (CLAUDE.md rule).

---

## 10. Screen inventory and states

| Screen | Loading | Empty | Error |
|---|---|---|---|
| Welcome | – | – | – |
| Join (invite, sign-in, name) | spinner on buttons | – | invalid invite; sign-in failed; network |
| Setup wizard | per-step spinner | – | per-step error + retry; 2-project limit; consent cancelled |
| Home | skeleton cards | "No frames yet" | offline banner; **paused space** banner; storage banners |
| Frame (grid) | skeleton tiles | "No photos yet" | load failed + retry; not a member any more → back to Home |
| Photo viewer | progressive image | – | image failed to load |
| Prepare | preview spinner | – | unreadable file ("Couldn't open this photo") |
| Upload queue | progress tiles | – | per-tile retry; quota; duplicate toast |
| Frame settings | skeleton rows | – | save failed (field reverts, toast) |
| Frame members / invites | skeleton | "Just you so far" + Invite | – |
| Add frame (BLE) | per-step | – | §6.2 table |
| Space: members | skeleton | – | – |
| Space: storage | skeleton | – | – |
| Space: admin | – | – | Supabase disconnected → Reconnect; update failed → retry |
| Account | – | – | delete failed |

**Space-wide states** shown as a banner on Home and Frame:
- **Paused** (any API returns HTTP 540): admin → "Your space is asleep because nobody used it for a week. **Wake it up** (about 3 minutes)." with progress; members → "Ask <admin> to open Ink Frame to wake the space up."
- **Update available** (admin, bundled schema newer): "An update for your space is ready. **Update** (a few seconds)."
- **App too old** (member, schema newer than the app knows): "Update Ink Frame to keep using this space."

---

## 11. Components

`FrameCard`, `StatusLine` (+ `SyncHint`), `PhotoTile` (states: ready / uploading with progress / failed), `PhotoGrid` (selection, reorder), `CropEditor`, `EinkPreview`, `LookPresets` + `DitherAdvanced`, `UploadBanner`, `SpaceSwitcher`, `ChecklistProgress` (wizard, BLE, restore), `InviteSheet` (QR, share, copy), `MemberRow`, `UsageBar`, `SettingRow` variants (picker, segmented, toggle, time range, time zone search), `Banner` (paused / update / storage / offline), `EmptyState`, `ErrorState`, `ConfirmDialog` (incl. typed confirmation), `SidebarLayout` (desktop two-pane).

---

## 12. Packages (final list for Phase 3)

| Package | Use |
|---|---|
| `supabase_flutter` | auth sessions, PostgREST reads, Storage signed URLs |
| `flutter_riverpod` | state |
| `go_router` | navigation, deep links |
| `google_sign_in` | Google on iOS/Android/macOS |
| `sign_in_with_apple` | Apple on iOS/macOS |
| `flutter_web_auth_2` | **new**: browser flows: Supabase OAuth (all platforms) and Google loopback on Windows/Linux |
| `universal_ble` | Bluetooth pairing |
| `image_picker`, `file_selector`, `desktop_drop` | photo input |
| `mobile_scanner` | QR scan |
| `qr_flutter` | **new**: show invite QR |
| `share_plus` | **new**: share invite links |
| `app_links` | `inkframe://` links |
| `url_launcher` | open Supabase dashboard, help pages |
| `flutter_secure_storage` | platform token, sessions, wizard progress |
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
| **3a** | Scaffold (iOS, Android, Windows, macOS), theme, routing, dev mode, data layer; **Join** with a pasted link; Google sign-in (mobile + Windows loopback), Apple on iOS/macOS; spaces list and switcher; Home with frame cards (read-only) | Join the dev space on Windows and a phone, see frames |
| **3b** | `lib/imaging/` port, indexed PNG encoder, golden tests (PLAN.md §8.3–8.4) | Golden parity passes in CI |
| **3c** | Frame screen, Prepare (crop/preview/presets/advanced), upload queue, viewer, delete, reorder | §12.2 steps 3–5 on Windows |
| **3d** | Frame settings, invites (sheet, `/join` page), members, storage, account (display name, delete account) | Phone joins by QR; usage matches `project_usage` |
| **3e** | **Spike (c)** first; setup wizard, admin tools (update, restore, rename, delete space), `central/` OAuth bounce page | §12.2 step 1 on Windows with a fresh project |
| **3f** | Add frame over Bluetooth (+ dev "pair with a code") | Pair `frame_sim` by code; BLE against a stub or the first firmware build |
| **3g** | Polish: empty/error state audit, accessibility pass, dark mode, desktop keyboard shortcuts, store assets prep | §12.2 passes on Windows and one phone |
