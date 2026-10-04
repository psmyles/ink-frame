# Frame pairing

How the app connects a frame (app-flow §6, PLAN.md §9.5): over Bluetooth LE it gives
the frame the Wi-Fi details, the frame's API address and a one-time pairing token; the
frame joins Wi-Fi and claims its place with `POST /device-api/claim`
(shared/api/openapi.yaml). UUIDs and limits: [shared/pairing.json](../shared/pairing.json).
App side: `app/lib/ble/` (built in 3f). Firmware side: `src/ble/provisioning.*` (4b).

## Advertising

- In **PAIRING** (first boot, or green button held 3 s) the frame makes a random
  6-digit **passkey**, shows it on screen with its name, and advertises for 10 minutes,
  then sleeps.
- Name `InkFrame-XXXX`, where `XXXX` is the last 4 hex digits of its `hw_id`, upper
  case, also shown on screen, so a list of several frames can be matched to the right one.
- The advertisement carries the service UUID (the app scans for it). The name goes in
  the **scan response**: flags + a 128-bit UUID + the name don't fit in 31 bytes.
- Connectable, one connection at a time.

## Security

- **LE Secure Connections, passkey entry**: the frame is *display only*, so the phone's
  OS asks for the passkey shown on the frame. Every characteristic needs an encrypted,
  authenticated (MITM) link, so the first read triggers pairing; the Wi-Fi password and
  the pairing token are never sent in plain text.
- The frame **doesn't keep bonds**: each PAIRING session needs its new code. The app
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
| `info` | `42a40002-…` | read | `{"hw_id","model_id","fw_version","frame_id"}` |
| `wifi_scan` | `42a40003-…` | write, notify | write `{"scan":true}`; one notification per network, then `{"done":true}` |
| `provision` | `42a40004-…` | write | `{"ssid","password","api_base_url","pairing_token"}` |
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
{"hw_id":"e1002-24ec4a1b2c3d","model_id":"reterminal-e1002","fw_version":"1.0.0","frame_id":null}
```

`frame_id` is the frame this hardware is linked to (from its last claim), or `null`.
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
{"ssid":"Home","password":"…","api_base_url":"https://<ref>.supabase.co/functions/v1","pairing_token":"01J9…"}
```

`password` is `""` for an open network. `api_base_url` is the frame's project URL +
`/functions/v1`; the frame calls `{api_base_url}/device-api/claim` and `/sync`. The app
asks for the pairing token (`POST /app-api/pairing-tokens`, 10 minutes, one use) just
before writing, so it's fresh.

The frame then reports progress on `status`. After `wifi_failed` or `error` it stays in
PAIRING and connected, ready for another `provision` (the app sends a corrected one).

### `status`

| `state` | Extra fields | Meaning | App shows |
|---|---|---|---|
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

After `ready` the frame disconnects within a few seconds. A disconnect after `claimed`
counts as done (the frame is linked; it gets its photos on its own); a disconnect before
it is "Lost the connection to the frame."

## Without Bluetooth

In developer mode, Connect the frame also offers **Connect with a code**: the app shows
a pairing token and the `frame_sim claim` command line (tools/frame_sim), and shows the
frame as connected once it has claimed.
