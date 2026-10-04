# Frame pairing

How the app connects a frame (app-flow §6, PLAN.md §9.5): over Bluetooth LE it gives
the frame the Wi-Fi details, the frame's API address and a one-time pairing token; the
frame joins Wi-Fi and claims its place with `POST /device-api/claim`
(shared/api/openapi.yaml). UUIDs and limits: [shared/pairing.json](../shared/pairing.json).
App side: `app/lib/ble/` (built in 3f). Firmware side (4b): `firmware/src/ble/ble_link.*` (Bluetooth),
`src/provision/pairing_mode.*` (the setup loop) and `src/provision/provisioning.*` (the steps,
shared with the serial console in developer builds).

## Advertising

- In **PAIRING** (first boot, or green button held 3 s) the frame makes a random
  6-digit **passkey**, shows it on screen with its name, and advertises for 10 minutes
  (kept up while the app is connected, at most 30), then sleeps. Before sleeping it
  redraws the screen without the code ("Asleep to save battery. Press the green button
  to set it up."), since the code is no longer valid.
- Name `InkFrame-XXXX`, where `XXXX` is the last 4 hex digits of its `hw_id`, upper
  case, also shown on screen (large, next to the passkey). The app always asks you to
  match it before connecting, even when it finds only one frame, so a neighbour's frame
  in PAIRING isn't taken by mistake.
- The advertisement carries the service UUID (the app scans for it). The name goes in
  the **scan response**: flags + a 128-bit UUID + the name don't fit in 31 bytes.
- Connectable, one connection at a time.

## Security

- **LE Secure Connections, passkey entry**: the frame is *display only*, so the phone's
  OS asks for the passkey shown on the frame. Every characteristic needs an encrypted,
  authenticated (MITM) link, so the first read triggers pairing; the Wi-Fi password and
  the pairing token are never sent in plain text.
- The frame **doesn't keep bonds**: each PAIRING session needs its new code (it bonds
  for the session, which phones expect, and deletes every bond when PAIRING starts and
  ends). The app
  removes the OS's bond when it's done (Android, Windows, Linux; Apple platforms can't),
  so the next pairing asks for the new code instead of failing on old keys.
- The app pairs by **reading `info`**: the encrypted read makes Android, iOS and macOS
  run pairing (the passkey prompt) and then retry the read. Only if the read is refused
  for lack of pairing does it ask for a bond explicitly (Windows and Linux don't pair by
  themselves). It doesn't bond before the first read: a peripheral that pairs on
  demand may refuse that (a Mac did).
- A wrong passkey fails pairing; the app says "The code didn't match" and tries again.

## Service and characteristics

| Name | UUID suffix | Properties | Content |
|---|---|---|---|
| service | `42a40001-…` | primary | |
| `info` | `42a40002-…` | read | `{"hw_id","model_id","fw_version","frame_id","sd"}` |
| `wifi_scan` | `42a40003-…` | write, notify | write `{"scan":true}`; one notification per network, then `{"done":true}` |
| `provision` | `42a40004-…` | write | `{"ssid","password","api_base_url","pairing_token","erase_sd"?}` |
| `status` | `42a40005-…` | notify | `{"state", …}`, below |

### Messages

Every message is one line of UTF-8 JSON ending in `\n` (JSON has no raw newlines),
at most 1024 bytes. A message larger than one ATT payload (MTU − 3; 20 bytes at the
default MTU) is split into chunks:
- **Writes** (app → frame): chunks of at most MTU − 3 bytes, written in order *with
  response*. The frame appends to a buffer until `\n`, then handles the line. A line
  over 1024 bytes, or JSON it can't read, gets `status` `{"state":"error","code":"bad_request"}`
  and the buffer is cleared.
- **Notifications** (frame → app): the same, chunks of at most MTU − 3 bytes; the app
  appends until `\n`.

The app asks for an MTU of 247 (Android ≤ 13 needs asking; other platforms negotiate
it themselves) and works with whatever it gets.

### `info`

```json
{"hw_id":"e1002-24ec4a1b2c3d","model_id":"reterminal-e1002","fw_version":"1.0.0","frame_id":null,
 "sd":{"state":"ok","total_bytes":7948206080,"free_bytes":5133828096,"cache_bytes":0,"other_bytes":2814377984}}
```

`frame_id` is the frame this hardware is linked to (from its last claim), or `null`.

`sd` is the memory card (one line in the real message; wrapped here):
- `state`: `ok`; `missing` (no card); or `unreadable` (the frame can't read it: not FAT16/
  FAT32, for example exFAT or NTFS as larger cards come, or damaged). Only `ok` has the
  sizes.
- `total_bytes`, `free_bytes`; `cache_bytes`: the frame's own photos (its cache, kept if
  this hardware reconnects to the same frame); `other_bytes`: everything else on the card,
  which the frame never touches unless it's erased.
- Absent from older firmware and pretend frames: the app then says nothing about the card.
The app reads `info` first (this read triggers pairing), then:
- `model_id` ≠ the frame's model → "This is a … but Kitchen is set up for a …" (app-flow
  §6.2), before any Wi-Fi.
- `frame_id` set and ≠ this frame's id → "This frame is still linked to another Ink
  Frame. Hold its green button for 10 seconds to reset it, then start again."
- `frame_id` = this frame's id → reconnecting the same hardware (new Wi-Fi, say).

### `wifi_scan`

The app subscribes, then writes `{"scan":true}` (again to rescan). The frame scans
(2.4 GHz only) and notifies each network, strongest first, hidden ones left out, each
SSID once (its strongest), at most 20:

```json
{"ssid":"Home","rssi":-52,"secure":true}
{"done":true}
```

### `provision`

```json
{"ssid":"Home","password":"…","api_base_url":"https://<ref>.supabase.co/functions/v1","pairing_token":"01J9…","erase_sd":true}
```

`erase_sd` (optional, default false): the frame **formats the memory card as FAT32**
(everything on it is lost) before joining Wi-Fi, reporting `erasing`, then re-reads it.
Formatting also makes an `unreadable` card usable, and uses the whole card whatever its
size (FAT32 on cards over 32 GB, which come as exFAT). If it fails, or there's no card,
`status` is `error` `sd_failed` and nothing else happens.

`password` is `""` for an open network. `api_base_url` is the frame's project URL +
`/functions/v1`; the frame calls `{api_base_url}/device-api/claim` and `/sync`. The app
asks for the pairing token (`POST /app-api/pairing-tokens`, 10 minutes, one use) just
before writing, so it's fresh.

The frame then reports progress on `status`. After `wifi_failed` or `error` it stays in
PAIRING and connected, ready for another `provision` (the app sends a corrected one).

### `status`

| `state` | Extra fields | Meaning | App shows |
|---|---|---|---|
| `erasing` | | formatting the memory card (`erase_sd`; a few seconds) | Erasing the memory card |
| `wifi_connecting` | | joining the network (15 s timeout) | Joining Wi-Fi |
| `wifi_failed` | `reason`: `auth` / `not_found` / `other` | couldn't join | back to the Wi-Fi step, with the reason |
| `claiming` | | `POST /claim` | Linking to Kitchen |
| `claimed` | `frame_id` | secret stored | ✓ Linking |
| `syncing` | | first `POST /sync`, downloading photos | Getting photos |
| `ready` | | done; the frame shows its first photo or "Ready" and leaves PAIRING | Done |
| `error` | `code`, optional `message` | see below | |

`error` codes:
- `invalid_pairing_token`: expired or used. The app asks for a new token and sends
  `provision` again, once, without bothering the user.
- `model_mismatch`, `unknown_model`: from `/claim` (the app's `info` check normally
  catches a mismatch first).
- `linked_elsewhere`: the frame holds a link to another `api_base_url`; a 10-second
  reset clears it.
- `unreachable`: on Wi-Fi but the API can't be reached (no internet, DNS, TLS).
- `server`: `/claim` failed some other way.
- `bad_request`: a message the frame couldn't read.
- `sd_failed`: `erase_sd` couldn't format the card (or there is none).

After `ready` the frame disconnects within a few seconds. A disconnect after `claimed`
counts as done (the frame is linked; it gets its photos on its own); a disconnect before
it is "Lost the connection to the frame."

## Without Bluetooth

In developer mode, Connect the frame also offers **Connect with a code**: the app shows
a pairing token and the `frame_sim claim` command line (tools/frame_sim), and shows the
frame as connected once it has claimed.
