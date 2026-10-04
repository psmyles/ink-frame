# Ink Frame app: flow and UI structure

> **Status:** APPROVED 2026-09-26 (Phase 2, PLAN.md §11). D1–D5 and D7–D11 accepted as recommended.
> Each section answers a question from PLAN.md §8.5. Details below are defaults that can still change during Phase 3.
> Revised 2026-09-26 for **one Supabase project per frame** (PLAN.md §2, §16).
> Revised 2026-10-04: the photos, the people and their storage are the **album**; **frame** means only the hardware (PLAN.md §2, §16). Quoted copy follows `app/lib/l10n/app_en.arb`.

---

## 0. Decisions for you (summary)

| # | Question | Recommendation |
|---|---|---|
| D1 | Navigation model | **Home = every album you're in**, whoever set it up. No switcher, no bottom tabs; Account opens from the header. Desktop uses two panes (§2) |
| D2 | Dithering control | **Automatic, no choices shown** (revised 2026-09-26 at the user's request): plain-language Brightness/Contrast/Colour and a dot pattern sit behind a collapsed "Adjust" (§3.3) |
| D3 | Upload queue | **In memory for v1**, with per-photo retry; a queue that survives an app restart comes later (§3.5) |
| D4 | Invite links | **HTTPS links** via a small page on GitHub Pages that opens the app, since `inkframe://` links aren't clickable in most messengers (§5.1). Needs a `central/` addition |
| D5 | Apple sign-in on Windows/Linux | **Not offered.** Google only, plus email/password in dev mode on dev projects (§7.1) |
| D7 | "Is my frame up to date?" | Record the manifest version the frame last received, so the app can say **"Up to date" / "Changes waiting"** (backend addition, §4.2) |
| D8 | Photo order UI | Offer drag-to-reorder **only when the frame is set to "In order"**; in shuffle it means nothing (§3.6) |
| D9 | Visual direction | Calm, photo-first "gallery" look, paper-white / charcoal, one Spectra-6 accent colour, platform fonts (§8) |
| D10 | Localization | English only in v1, but every string in ARB files from day one (§8.4) |
| D11 | Links carry which key | Use the project's short **publishable key** (`sb_publishable_…`) in invite and "another device" links, so QR codes stay small (§1.4) |

(D6, a "space name", is gone: each album's own name is what people see.)

### Words used in the app
| Say | Don't say |
|---|---|
| **album** ("Kitchen"): the photos, the people and their storage; each frame has one | space, project, frame (for the photos) |
| **frame**: only the hardware (its screen, buttons, battery, Wi-Fi, memory card) | device (that's the phone or computer), hardware |
| **owner** / "Set up by Priya" | admin |
| **people** / "Shared with 4 people" | members |
| **Invite someone to add photos** | join a space |
| "**checks for new photos** once a day" / "**last checked** 3 h ago" | sync, manifest |
| **Connect the frame** | pair, claim, provision |
| "**asleep because it wasn't used for a while**" | paused, restore |
| "your free **Supabase account**" (setup only) | backend, database, project |

If it would still exist after the hardware was thrown away, it's the album.

---

## 1. First run

### 1.1 Welcome
Signing in always comes first (changed 2026-10-04; it was "I've been invited" / "Set up a frame" / "Already use Ink Frame? Sign in").
```
┌─────────────────────────────┐      ┌─────────────────────────────┐
│        [frame illustration]  │      │        [frame illustration]  │
│         Ink Frame            │      │        No albums yet         │
│  Your family's photos on     │      │  There are no albums on this │
│  e-ink frames.               │ ───► │  account yet. Set up a frame │
│                              │ none │  to start your own album, or │
│  [ Continue with Google ]    │      │  join one with an invite. …  │
│  [ Continue with Apple ]     │      │  [ I've been invited ]       │ ← primary: most people are invited
│  Your account is only used   │      │  [ Set up a frame ]          │
│  to recognise you, …         │      │  Use a different account     │
└─────────────────────────────┘      └─────────────────────────────┘
```
- **Continue with Google/Apple** (and email/password in developer mode) → "Looking for your albums…": the directory (§1.4) lists the account's albums, the app signs in to each, then **Home**. Albums you were removed from, or that no longer exist, are skipped and taken off the list.
- **None found** → the right-hand screen. **I've been invited** and **Set up a frame** reuse this sign-in (it stays usable for about 50 minutes), so neither asks again. **Use a different account** goes back to signing in, and Google asks which account.
- **Couldn't look** (offline, the directory down, an album asleep): the same screen with the reason and **Try again** in place of "No albums yet", so setting up or joining is never blocked. Without a directory, or with a developer email sign-in, it goes straight to that screen without the "on this account" sentence.
- Coming back to Welcome with the sign-in still recent (after leaving your last album) opens the right-hand screen; after **Sign out** or deleting the account it starts with signing in.
- An invite link opened from outside the app still goes straight to Join (§1.2), which asks to sign in there if there's no recent sign-in.

### 1.2 Join an album (invited)
1. **Get the invite**: one of
   - opened from an invite link (skips this screen),
   - **Scan QR** (mobile),
   - **Paste link** (all platforms; desktop's main path). A bare code isn't enough because the app also needs the album's address, so the paste box asks for the whole link ("Paste the whole link you were sent. The code on its own isn't enough.").
2. **Sign in**: skipped after signing in on Welcome (§1.1); otherwise "Continue with Google" / "Continue with Apple" (per platform, §7.1). Copy: *"Your account is only used to recognise you, and to find your albums when you sign in on a new phone or computer."* Joining a second album reuses the same sign-in without asking again. After joining, the album goes on your list in the directory (§1.4).
3. **Your name**: "What should the others see?" For the first album it's empty (with the Google/Apple first name as a suggestion chip); for later albums it's pre-filled with the name you used before.
4. `POST /invites/accept` → the **album** screen, with a one-time tip: *"Add photos with the + button. The frame checks for new photos once a day, or press its green button to check now."*

Errors: invalid/expired/used invite → "This invite has expired or was already used. Ask for a new one." (single message for all, matching the API). Sign-in cancelled → back to step 2, no error.

### 1.3 Set up a frame (owner)
One screen with a **checklist that fills in**, so it's clear what's happening and where it stopped.

```
Set up a frame
 ✓ Connect your free Supabase account     [explainer card]
 ✓ Which frame do you have?               reTerminal E1002 7.3″  (picture of each model)
 ✓ Name the album                         Kitchen · Time zone: Europe/Berlin
 ● Getting its photo storage ready…       ~ a few seconds
 ○ Turning on sign-in
 ○ Signing you in
 ○ Connect the frame                      [Connect now]  [Later — add photos first]
```

- **Explainer card** (before connecting): each frame has its own **album** (its photos and the people you share them with), kept in *your own* free Supabase account; you'll be its owner; one free account can run **2 albums**; nobody else (including us) can see the photos.
- **Connect Supabase** opens the browser (Supabase OAuth, PLAN.md §6.2). Skipped when the owner's account is already connected (their second album). Dev mode shows "Paste access token" instead.
- **Which frame do you have?**: the list of models with a picture, name and screen size. This fixes the resolution and colours for every photo (PLAN.md §2). Changing it later clears the photos (§4.3).
- **Name and time zone**: name required ("Kitchen", "Grandma's"); time zone defaults to the phone's.
- **Region** isn't asked: suggested from the time zone (`region_selection: smartGroup`), changeable under "More options".
- The storage steps run automatically (measured ~17 s). Each step is **idempotent and resumable**: the ref and progress are saved in secure storage after each step, so closing the app or a failure resumes from the failed step.
- **Failure** shows on the failed row: plain explanation + **Try again**. Special cases:
  - *2-album limit* → "Your free Supabase account already runs 2 projects, the most a free account can. Someone else in the family can set up this frame with their own free account, or you can delete a project you don't need in Supabase." + **Open Supabase**.
  - *Browser consent cancelled* → back to step 1.
- **Connect the frame** goes to §6; **Later** lands on the empty album screen, where photos can be added before the hardware arrives.

**Built in 3e** (differences from the sketch above): the form has the three numbered sections (connect, model as a list of names and sizes without pictures yet, then name, time zone and **your name**, the name the others see) and **Set up Kitchen**; then the checklist has three rows (photo storage, sign-in, signing you in), with "Usually under a minute" on the first. "Signing you in" reuses a recent Google/Apple sign-in, else shows the buttons. A setup that stopped shows "Setting up Kitchen stopped before it finished." with **Continue**; **Cancel setup** deletes what was made in the Supabase account. The end is "Kitchen is ready" with **Connect the frame** and **Later — add photos first** (3f). Region is never asked (no "More options").

### 1.4 Returning on a new device
The app needs each album's address to sign in. A new device has none, and it may be the only device the person has left, so signing in alone has to be enough. The **directory** (`central/directory/`, `shared/api/directory.yaml`) keeps, for each Google or Apple account, the addresses of the albums it's in. Addresses (project URL + publishable key) aren't secret; the directory stores a hash of the account ID, not names or emails.

- Signing in on Welcome (§1.1) is the whole flow: "Looking for your albums…" → signed in to each → Home. Albums you've since been removed from are skipped and taken off your list, without a note.
- **Nothing found**: "No albums yet" with set up / join (§1.1), and "If you used a different account before, try that one." Offline: "Can't look for your albums right now…"
- **A link or QR code instead** (also the only way for dev-mode email accounts): **Account → "Use on another device"** on a device you still have shows a QR and a link holding the addresses of **all** your albums (no invite codes): `…/join#u=<url1>&k=<key1>&u=<url2>&k=<key2>`. On the new device: sign in, then **I've been invited** → scan or paste it. Any invite link works too.
- **Keeping the list**: joining (or signing in with a link) adds albums; leaving takes the album off; Delete my account removes the account from the directory; sign out only forgets this device's directory token. Changes that can't be sent (offline) go out when the app next starts. The app never waits for the directory, and works without it.
- An owner on a new device also reconnects Supabase from the album's settings (§4.4) to regain owner tools.
- **Albums added on another device** (built in 3g): the app asks the directory at start and on refresh. Albums on the account but not on this device show as a card on Home (and in the desktop sidebar): "1 more album is on your account. It was added on another device. Sign in again to see it here too." **Add to this device** (Google or Apple, whichever found the account) / **Not now** (until the next start). No names: the directory doesn't keep them.

---

## 2. Navigation

### 2.1 Map
```
Welcome ─┬─ Invited → Join ───┐
         └─ Set up a frame ───┤
                              ▼
Home (every album you're in)
 ├─ Album
 │   ├─ Photo viewer (swipe; info; delete)
 │   ├─ Add photos → Prepare (crop/preview/adjust) → Upload
 │   ├─ Settings (owner edits; others read)
 │   ├─ People (invite, remove, leave)
 │   └─ Storage
 ├─ Set up a frame (wizard, §1.3)
 ├─ Join an album (paste/scan an invite)
 └─ Account: your name, use on another device, sign out, delete account, about, dev mode
```

### 2.2 Mobile
- **Home** is a list of album cards; each shows "Set up by Priya" when it isn't yours. Header: app name and an **avatar** button (→ Account). A "+" button offers **Set up a frame** / **Join with an invite**.
- Drill-down navigation with a back button; **no bottom tabs** (D1).
- On an album screen, **"+"** = Add photos; the header has Settings (⚙) and People (👥).

### 2.3 Desktop (Windows first; macOS/Linux same)
```
┌───────────────┬────────────────────────────────────────────────┐
│ Ink Frame     │  Kitchen                       ⚙  👥  [+ Add photos]│
│               │  Up to date · last checked 3 h ago · 🔋 80%      │
│ ALBUMS        │ ┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐            │
│ ▸ Kitchen     │ │    ││    ││    ││    ││    ││    │            │
│   Grandma's   │ └────┘└────┘└────┘└────┘└────┘└────┘            │
│   (set up by  │  … photo grid, drop files anywhere to add …     │
│    Priya)     │                                                  │
│ + Set up / join│                                                 │
│ Account       │                                                  │
└───────────────┴────────────────────────────────────────────────┘
```
- **Two panes** from ~900 px wide: sidebar (albums, set up / join, Account) and detail. Below that width, the mobile layout.
- **One app, one set of screens.** The layout is chosen by **window width only**, never by platform, so narrowing the desktop window shows exactly the phone layout (and widening a tablet shows two panes). Gestures work with both touch and mouse everywhere (long-press also works with a mouse; hover is an extra, never the only way). What width can't change is the platform plumbing: sign-in sheets, the photo library picker, the QR camera, the share sheet and Bluetooth, each of which has a desktop path (§6.3, §7.1).
- **Drag and drop** files onto the window (or onto an album in the sidebar) → Prepare.
- Keyboard: Delete removes selected photos (with confirm), Ctrl/Cmd+A selects all, arrows move in the viewer, Ctrl/Cmd+V pastes an invite link anywhere on Welcome/Join.
- Prepare (the editor) opens **full window**; settings, people and storage open as **side sheets**.

---

## 3. Photos

### 3.1 Album screen (photo grid)
- Grid of photos **in the order the frame uses** (by position). Tiles show the e-ink preview colours. A small initial in the corner; long-press (mobile) / hover (desktop) shows "Added by Alice · 3 days ago". Deleted accounts show "Someone who left".
- **Header status** (§4.2).
- **Selection**: long-press (mobile) or checkbox on hover / Shift-click (desktop) → action bar: **Delete** (only if every selected photo is yours or you're the owner; otherwise the button explains why).
- **Empty state**: "No photos yet. Add some and the frame will show them after it next checks." + Add photos.

### 3.2 Add photos: pick
- Mobile: `image_picker` multi-select. Desktop: file dialog or drag-drop. Formats: JPEG, PNG, WebP, HEIC (iOS/macOS only).
- The target is the album you're in. (Sending one photo to several albums, processed for each one's model: later.)
- **Share from another app** (phones): Photos, Gallery, Files or a browser → Share → **Ink Frame** (up to 30 photos on iPhone). The app opens on the album and goes straight to Prepare; with several albums it first asks **"Add the photos to which album?"**; with none it says to set up or join an album first. Android: `ShareActivity` hands the photos to the app's own task, which copies them into an inbox folder. iPhone: a share extension copies them into a folder shared with the app (app group `group.com.psmyles.inkframe`) and opens the app; if it can't, it says "Open Ink Frame to finish adding the photos", and the app picks them up when it next comes to the front.

### 3.3 Prepare (overview, then edit one photo)
Reworked 2026-10-02 after trying it on desktop: the old single screen hid how to crop, and Adjust opened behind the photo strip.

**Overview** (several photos picked):
```
┌──────────────────────────────────────────┐
│ ✕  Prepare                       [⇧ Upload 5]│
│ one-line hint                            │  "How they'll look on the frame. Tap one to adjust."
│ ┌──────────────┐ ┌──────────────┐        │  grid of frame looks (1 column on phones,
│ │            ✕ │ │            ✕ │        │  more on wider windows); ✕ removes one
│ │      [✎ Edit]│ │  Preparing…  │        │
│ └──────────────┘ └──────────────┘        │
│ [        + Add more photos             ] │  a plain button under the grid
└──────────────────────────────────────────┘
```
- Every photo is shown **as it will look on the frame** (Automatic, centre crop) without opening anything. Most people check them and press **Upload N**.
- Previews render in the background: the photo open in the editor first, then the rest in order. Each photo gets a quick frame look straight away, then Automatic's search tunes it and the tuned look replaces it (PLAN.md §8.3 has the timings). A photo shows its plain crop with "Preparing…" only until its first frame look is ready.
- **Add more photos** (a button under the grid, not a tile that could pass for an empty photo) picks more photos into the same batch. The title is just "Prepare": the count is on Upload, and both fit in a narrow window.
- Closing (✕ or back) asks **"Leave without uploading?"** when more than one photo was picked or anything was changed.

**Editor** (tap a photo; a single picked photo opens here directly, with ✕ and Upload instead of Done):
```
┌──────────────────────────────────────────┐
│ Photo 2 of 5                 ‹  ›  [Done]│
│ ┌──────────────────────────────────────┐ │
│ │  frame-shaped window = the crop      │ │  drag to move, pinch / scroll to zoom,
│ │  (shows the frame look at rest)      │ │  double-tap to re-centre
│ └──────────────────────────────────────┘ │
│  Drag the photo to move it. Pinch to zoom.│
│  [   ⟳ Rotate   ] [ ◐ View original ]    │  always one row
│ ──────────────────────────────────────── │
│ Automatic                         [on]    │  scrolls on its own; the photo stays put
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │  faint line after each section
│ Brightness  ─────────●─────────           │
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│ Contrast    ─────────●─────────           │
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│ Colour      ─────────●─────────           │
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│ More options ▸   (Dot pattern)            │
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│ [ ✓✓ Use for all ]  [ ⟲ Start over ]      │
└──────────────────────────────────────────┘
```
- **The preview is the crop.** The frame-shaped window shows the frame look; dragging it moves the photo, and pinch (touch), scroll or trackpad pinch (computers) zooms. The parts that will be cut off always show dimmed around the window, so it's clear there's more photo. While moving, the window shows the photo itself; about a third of a second after it stops, the frame look comes back. Aspect locked to the frame's model; centre crop by default; rotate in 90° steps.
- **View original** shows the photo instead of the frame look while held (its tooltip says so).
- **No waiting on changes, no Apply button:** a slider change shows its frame look a moment later (the previous look stays up with "Updating…" meanwhile, never flashing back to the photo). After the crop moves, a quick look uses Automatic's previous settings, and the tuned look follows once the photo has been still for half a second.
- **Layout:** the canvas never scrolls away. Narrow windows: canvas on top, controls scroll below it. Wide or landscape windows: canvas on the left, controls in a side panel (the hint and buttons stay under the canvas when there's height for them).
- **Adjustments** are visible in the editor without a heading (you only get here by choosing to change a photo), plain words only, no end labels on the sliders, and apply to **this photo**: **Use for all** copies them to the rest.
  - **Automatic (recommended)**: on by default.
  - **Brightness**, **Contrast**, **Colour**: sliders centred on Automatic's choice (or on neutral when Automatic is off).
  - **More options ▸**: **Dot pattern**: *Fine* (default), *Smooth*, *Crisp*, *Grid*, *Grainy*.
  - **Start over** undoes the crop, rotation and adjustments (next to Use for all, same button style).
  - Words avoided in the UI: dither, kernel, error diffusion, serpentine, Bayer, gamma, saturation.
- ‹ › step through the photos; **Done** returns to the overview.
- **Upload N** starts the queue and returns to the album screen.

#### 3.3.1 Automatic
Chosen by measurement (`app/test/imaging/fidelity_bench_test.dart`, 12 real photos) against opendithering's Auto-tune, which the user asked for as the default; the details and numbers are in PLAN.md §8.3.

### 3.4 Processing and upload
Per photo: crop → resize → dither → indexed PNG → sha256 → `request-upload` → PUT → `finalize` (PLAN.md §8.3). The grid shows **placeholder tiles** at the end of the grid, saying **Waiting…**, **Preparing…** or **Uploading…** (words only: a photo is one ~50 KB file, so there's no real progress to show).

### 3.5 Upload errors (D3)
- Failed tiles show **Retry** / **Remove**. "Retry all" in a banner when several fail.
- *Already in this album* (409): the tile disappears with a toast "1 photo was already in the album".
- *Storage full* (quota): stop the queue; banner "Kitchen's storage is full. Delete some photos to add more." (§5.3).
- Mobile: if the app goes to the background mid-queue, it keeps going while the OS allows; on return, unfinished items show Retry.

### 3.6 Order and viewer
- **Reorder** (owner only, D8): when the frame is set to "In order", the header has **Change order**, which opens the photos as a list with drag handles (Flutter has no reorderable grid; a list is also easier to drag on a phone). Each drop = one `POST /images/reorder`. In "Shuffle" there's no reorder.
- **Viewer**: tap a tile → full-width preview, swipe between photos, info line, Delete. **No re-editing**: only the processed PNG is stored, so to change a crop you delete and add again (the viewer says so).

---

## 4. The album and its frame

### 4.1 Home: album cards
Card = latest photo as the cover, name, "Set up by …" when it isn't yours, and one status line: "Up to date · last checked 3 h ago" / "The frame gets the changes around 18:00" / "⚠ The frame hasn't checked in since Tuesday" / "No frame connected yet". Empty Home: "No albums yet" + **Set up a frame** and **I've been invited**.

### 4.2 Status and "when will it change?" (D7)
- **Up to date** when the frame has received the latest changes; otherwise **"The frame gets the changes around 18:00"** (or "soon").
- **Next check**: `last_seen_at + sync_interval_s` shown as a time.
- **Always-visible hint** under the status: *"To show changes now, press the green button on the frame."*
- **Warnings**: not seen for more than 2× the check interval → "The frame hasn't checked in since Tuesday. Check its Wi-Fi and battery." Battery below the frame's **low battery warning** level (owner setting, §4.3; default 20 %, Off = no warning) → "Battery low (15 %)". No frame → "No frame connected yet" + **Connect the frame** (owner).
- The album screen header shows the same plus battery and signal.

### 4.3 Settings (owner edits; others see them read-only)
Grouped (2026-10-04) as **Album** (name, storage), **The frame** (the hardware: its 4 characters, software and battery, memory card, model, connect / disconnect), then **Showing photos**, **Checking for new photos**, **Battery** and, for the owner, **Owner tools**.

| Setting | Control | Values |
|---|---|---|
| Name | text | 1–40 chars |
| Change photo every | picker | 1 h, 2 h, **4 h**, 8 h, 12 h, 1 day, 2 days |
| Order | segmented | **Shuffle** / In order |
| Quiet hours | toggle + two time pickers | e.g. 22:00–07:00; "The frame won't change photos during these hours" |
| Time zone | searchable list | defaults to the owner's phone; shown as "Europe/Berlin (CET)" |
| Check for new photos | picker | 1 h … 2 days, **1 day**; hint: "More often uses more battery" |
| Low battery warning | picker | Off, 10 %, **20 %**, 30 %; "Shows a warning when the battery drops below this." App-only (the hardware never gets it), so it only says "Saved" and doesn't make the frame "Changes waiting". Notifications for it come in 3g (who gets them: decided then; default the owner) |
| Notify me when it's low | switch (phones) | Per person and phone: on by default for the owner, off for others; "On this phone." Says why when it can't (warning off, notifications blocked, the frame needs an update). Built in 3g |
| Frame model | read-only row + "Change" | changing warns "All N photos will be removed, because they were made for the <old> screen", then clears them |
| The frame | status + actions | "Frame F7C4" (the 4 characters its setup screen shows; the last 4 of `hw_id`) with "Connected · software 1.0.2 · Battery now: 80 %", or "No frame connected yet" · **Connect a different frame** (same model keeps the photos) · **Disconnect** (the frame wipes itself at its next check) |
| Memory card | read-only row (added 2026-10-04) | "2 GB of 32 GB used · its photos take 312 MB", from the frame's last check; "No memory card, or the frame can't read it. Put in a microSD card, or erase it when you connect the frame."; and, when the photos don't all fit (their total > free + what they take − 8 MB): "Kitchen's photos don't all fit on the frame's memory card (170 MB too much). Remove some photos, or put a bigger card in the frame." Not shown until the frame reports its card |

Each change saves immediately (`PATCH`) with a small "Saved · the frame gets it at its next check" (name and battery warning: just "Saved"); a failed save says "Couldn't save. Try again." and shows the old value. Everyone else sees **plain values** with "Only Priya can change these settings." (greyed-out controls would hide which option is set). The Album group has a **Storage** row ("312 MB of 1 GB" → §5.3). Built in 3d: everything except Frame model "Change" (3e) and the hardware actions (3f). On a wide window Settings, People and Storage open as a side sheet from the right; on narrow ones, full screen.

### 4.4 Owner tools (bottom of Settings, owner only)
- **Supabase account**: connected / **Reconnect** (after a reinstall or on a new device).
- **Update**: shown when the app has a newer backend than this album ("An update for Kitchen is ready · a few seconds").
- **Delete this album**: typed confirmation of the name; explains that all photos and everyone's access go, its storage in your Supabase account is deleted, and the frame keeps showing its last photos until it's reset. Uses the Management API (`DELETE /v1/projects/{ref}`).
- **Wake up** (on the asleep banner of the album screen, owner only; others are told to ask the owner): restores the project with a progress dialog, "about 3 minutes" (§6.4 of PLAN.md).
- Built in 3e, under an "Owner tools" heading; the Model row in "The frame" has **Change** (warns how many photos go). Every tool asks to connect Supabase first if this device isn't connected. Update also appears when only the functions changed (PLAN.md §6.2 step 10).

---

## 5. People

### 5.1 Invites (D4)
- **Album → People → Invite someone** (owner): a sheet (dialog on wide windows) with a **QR code**, the **invite code**, **Share link** (system share sheet), **Copy link**, and **Copy code**. Options (collapsed): "Works for 1 person / up to 10 people", "Expires in 1 day / **7 days** / 30 days". An invite with the defaults is made as soon as the sheet opens; changing an option makes a new one and revokes the one shown before.
- **Joining by QR** (phones): Join and "Already use Ink Frame? Sign in" have **Scan QR code** above the paste field; computers paste.
- **Link format**: `https://<pages-domain>/join#u=<project_url>&k=<publishable_key>&c=<code>`. The page shows "Open in Ink Frame", store badges, and the code as text. Everything after `#` never reaches the server. The app registers `inkframe://join?...` too; the page redirects to it.
- **Active invites** list under the people, with **Cancel invite** (owner).

### 5.2 People list
- Each person: name, "Owner" badge on the one who set it up, "You". The owner can **Remove** someone (confirm: "Their photos stay; you can delete them"); anyone else can **Leave this album**.

### 5.3 Storage
- Album → Storage: a bar "**312 MB of 1 GB** (free Supabase plan)", then per-person breakdown (the owner sees everyone; others see themselves). A note: "This is the album's online storage. The copies the frame keeps on its memory card aren't counted."
- Banner on the album screen at **80 %** ("Storage is getting full") and at the limit (uploads blocked, §3.5).
- **Quota values** (PLAN.md §15): recommend only the frame limit (≈ 90 % of 1 GB) in v1, no per-person limits.

---

## 6. Connect the frame (Bluetooth)

Reached from setup (§1.3), from "No frame connected yet", or from Settings → The frame → Connect a different frame. Owner only.

### 6.1 Steps
1. **Get ready**: illustration: "Hold the frame's green button for 3 seconds until it shows a 6-digit code." (First-time frames show it on power-up.)
2. **Find**: scan for `InkFrame-XXXX`, then **always ask** (changed 2026-10-04; one frame used to be picked by itself): one found → "Is this your frame? Check that the frame's screen shows the same 4 characters." with `XXXX` large, **Yes, connect** / **Not this one? Look again**; several → a list, each with its `XXXX` large. Nothing connects until you've matched it.
3. **Connect**: "Connecting to InkFrame-XXXX…"; the OS pairing prompt asks for the 6-digit code shown on the frame. Then the Wi-Fi step starts with "✓ Connected to InkFrame-XXXX".
4. **Wi-Fi**: networks the frame can see (from `wifi_scan`), strongest first; pick one, and the list folds away to just that network with **Choose another network** (changed 2026-10-04: a long list pushed the password and Connect out of sight); enter the password (show/hide; Enter connects like the button). Note: *"The frame needs a 2.4 GHz network. If your Wi-Fi has two names, pick the one without “5G”."* "Other network…" for hidden SSIDs. Below, **Memory card** (from `info.sd`, added 2026-10-04): "32 GB card, 30 GB free", "10 MB of other files on it stay, unless you erase it.", a warning if the frame's photos won't fit, and **Erase the memory card first** ("Deletes everything on it and sets it up for the frame."; off by default, on for a card it can't read: "The frame can't read its memory card. It may be set up for a camera or computer, or be damaged. Erasing it makes it work here."). No card: "There's no memory card in the frame. It needs one to keep photos…" Firmware that doesn't report its card shows nothing.
5. **Finishing**: a checklist driven by `status` notifications: (Erasing the memory card →) Joining Wi-Fi → Linking to Kitchen → Getting photos → **Done**. The frame's screen shows its first photo, or "Ready. Add photos to its album in the Ink Frame app."

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
| Different model (`model_mismatch`) | "This frame is a <other model>, but Kitchen is made for a reTerminal E1002. Switch Kitchen to the <other model>? Its N photos will be removed." → Switch (clears, retries) / Cancel. (Can't happen while the E1002 is the only model; kept for later models.) |
| Frame linked to another album | "This frame is still linked to another album. Hold its green button for 10 seconds to reset it, then start again." |
| Connection lost mid-way | "Lost the connection to the frame." Retry from step 2 |
| Erasing failed (`sd_failed`) | "The frame couldn't erase its memory card. Check it's pushed in properly, or try another card." Back to step 4 |

### 6.3 Without Bluetooth (desktop testing, dev mode)
"Connect the frame" offers **Connect with a code (developer)**: shows a pairing token to paste into `frame_sim claim`. The frame shows as connected after its first check.

**Built in 3f** (protocol: docs/pairing.md): one full-screen page that moves through the steps. Get ready shows a drawing of the frame with its name and code and the green button, and, when hardware is already connected, "The frame now showing Kitchen stops once this one is connected. The photos stay in the album." Find auto-picked a single frame after 2 s (now: always asks, §6.1). The model and link checks happen right after pairing (from `info`), before Wi-Fi. Wi-Fi failures say why when the frame knows (wrong password / network not found / other), plus "The frame joined Home but couldn't reach the internet." Finishing has three rows (Joining Home, Linking to Kitchen, Getting photos); the end is "The frame is connected to Kitchen" + "It shows a photo in a moment. Photos you add appear at its next check, or press its green button to check now." The frame screen shows **Connect the frame** under "No frame connected yet" (owner), and hides the green-button hint until a frame is connected. Settings → The frame: **Connect a different frame** and **Disconnect** (confirm: "It clears its photos and settings at its next check. The photos stay in Kitchen, ready for another frame."), or **Connect the frame**. "Open settings" for a refused Bluetooth permission exists on iOS and macOS only (Android asks again on Try again). Connect with a code waits for the claim (a new `hw_id`, or the same one checking in again). To try it on a phone before the firmware: `tools/ble_frame`.

---

## 7. Accounts and platforms

### 7.1 Sign-in per platform (D5)
| Platform | Offered |
|---|---|
| iOS, macOS | Apple, Google |
| Android | Google |
| Windows, Linux | Google (browser, loopback) |
| Any, dev mode + dev project | + email/password |

Consequence to accept: someone who joined with **Apple** on an iPhone can't sign in on Android/Windows with that account in v1; they'd join again with Google (a second person in the album). Copy on the iOS sign-in screen: "Use Google if you also want to use Ink Frame on Android or a computer."

### 7.2 Account screen
- **Your name** (edit): applies to every album you're in (the app updates each).
- **Use on another device** (§1.4).
- **Sign out**.
- **Delete my account** (albums you set up need your Supabase account connected; it asks if not): lists your albums. For albums set up by others: you leave, with an "Also delete my photos" checkbox. For albums you own: they are **deleted** (shown by name, with the §4.4 warning). One typed confirmation for the lot.
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
| Welcome (sign in first) | "Looking for your albums…" | "No albums yet" + I've been invited / Set up a frame | sign-in failed; couldn't look (offline, asleep) + Try again |
| Join (invite, sign-in, name) | spinner on buttons | – | invalid invite; sign-in failed; network |
| Set up a frame | per-step spinner | – | per-step error + retry; 2-frame limit; consent cancelled |
| Home | skeleton cards | "No albums yet" | offline banner; per-card asleep / not checked in |
| Album (grid) | skeleton tiles | "No photos yet" | load failed + retry; removed from the album → back to Home with a note |
| Photo viewer | progressive image | – | image failed to load |
| Prepare | "Preparing…" on the photo | – | unreadable file ("Couldn't open this photo") |
| Upload queue | tiles saying Waiting… / Preparing… / Uploading… | – | per-tile retry; storage full; duplicate toast |
| Settings | skeleton rows | – | save failed (field reverts, toast) |
| People / invites | skeleton | "Just you so far" + Invite | – |
| Storage | skeleton | – | – |
| Connect the frame | per-step | – | §6.2 table |
| Account | – | – | delete failed (per album, retry) |

**Per-album states** shown as a banner on the album screen and a badge on its Home card:
- **Asleep** (any API returns HTTP 540): owner → "Kitchen's photo storage is asleep because it wasn't used for a while. **Wake it up** (about 3 minutes)." with progress; others → "Kitchen is asleep because it wasn't used for a while. Ask Priya to open Ink Frame to wake it up." The frame keeps showing its photos meanwhile.
- **Update ready** (owner, bundled backend newer): "An update for Kitchen is ready. **Update** (a few seconds)."
- **App too old** (backend newer than the app knows): "Update Ink Frame to keep using Kitchen."
- **No memory card** (the frame reported `sd_total_bytes` 0): a line under the status, "No memory card"; on the Frame screen the full message (§4.3). **Photos don't fit** on the card: a notice on the Frame screen (§4.3).
- **No longer exists** (its project was deleted: HTTP 410, or its address is gone while Supabase answers): "Kitchen no longer exists: its photo storage was deleted." **Remove from this device** (also off your account's list). The same button follows "You're no longer in this album."

---

## 11. Components

`FrameCard`, `StatusLine` (+ `CheckHint`), `PhotoTile` (states: ready / waiting, preparing or uploading / failed), `PhotoGrid` (selection, reorder), `CropEditor`, `EinkPreview`, `LookPresets` + `DitherAdvanced`, `UploadBanner`, `ModelPicker`, `ChecklistProgress` (setup, connect, wake up), `InviteSheet` (QR, share, copy), `PersonRow`, `UsageBar`, `SettingRow` variants (picker, segmented, toggle, time range, time zone search), `Banner` (asleep / update / storage / offline), `EmptyState`, `ErrorState`, `ConfirmDialog` (incl. typed confirmation), `SidebarLayout` (desktop two-pane).

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
