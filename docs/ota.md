# Firmware updates

Frames install new firmware by themselves from a public, signed feed (PLAN.md §10). No
family's Supabase project is involved.

## The feed

`https://psmyles.github.io/ink-frame/firmware/<model_id>/manifest.json`, next to the image
it names. The Pages workflow (`.github/workflows/pages.yml`) copies both there from the
newest `fw-v*` GitHub release on every deploy.

```json
{
  "model_id": "reterminal-e1002",
  "version": "0.2.0",
  "url": "https://psmyles.github.io/ink-frame/firmware/reterminal-e1002/0.2.0.bin",
  "size": 1344761,
  "sha256": "…64 hex…",
  "min_battery_pct": 30,
  "rollout_percent": 100,
  "signature": "…128 hex: ECDSA P-256 r || s…"
}
```

The signature covers this text, built from the fields above (each line ends with `\n`):

```
inkframe-firmware 1
model reterminal-e1002
version 0.2.0
url https://psmyles.github.io/ink-frame/firmware/reterminal-e1002/0.2.0.bin
size 1344761
sha256 <hex>
min_battery_pct 30
rollout_percent 100
```

`firmware/src/core/firmware_update.cpp` and `tools/firmware/release.ts` build it the same
way; both have a test with the same expected string.

## On the frame

Release builds (`pio run -e release`) check the feed after a successful check for photos,
at most every 20 hours, and every time the green button is pressed (`src/net/ota.cpp`).
A frame installs a release only if all of these hold:

- the signature is from a key in `firmware/src/net/ota_keys.h`;
- it's for this model;
- its version is higher than the running one (MAJOR.MINOR.PATCH; anything after, like
  `-dev`, is ignored). Frames never go back to a lower version;
- this frame is in the rollout: FNV-1a of its `hw_id`, mod 100, is below `rollout_percent`;
- the battery is at `min_battery_pct` or more;
- this version hasn't already failed to start here twice.

It then streams the image into the other app slot, checking the size and SHA-256 as it
goes, lets the ESP-IDF check the image, makes it the one to start, and restarts.

**The trial.** A new firmware's first start checks for photos straight away (with a second
try 10 seconds later). It keeps itself if that works, or if the frame turns out to be
removed from its album. If both tries fail, it goes back to the previous firmware. If it
crashes first, or hangs for 10 minutes, the frame restarts and the bootloader goes back by
itself. Arduino-ESP32 2.0.17's bootloader and app are built with
`CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE` / `CONFIG_APP_ROLLBACK_ENABLE`, and the firmware
defines `verifyRollbackLater()` so the trial, not Arduino's start-up code, decides. How
often each version was tried is kept in NVS (namespace `ota`, which a factory reset keeps).

What a check reports (`console.py ota` shows it; the frame logs it):

| Status | Meaning |
|---|---|
| `installed` | Restarting into the new firmware's trial |
| `up_to_date` | The feed's version isn't higher |
| `not_yet` | Outside the rollout so far |
| `low_battery` | Below `min_battery_pct` |
| `gave_up` | This version failed to start here twice |
| `other_model` | The manifest is for another model |
| `no_feed` | No answer, or no release yet (404) |
| `bad_manifest` | Not a manifest the frame can read |
| `bad_signature` | Not signed by a listed key: nothing is downloaded |
| `download_failed` | The image didn't arrive in full |
| `bad_hash` | The image isn't the one the manifest names: nothing is installed |
| `flash_failed` | Writing or checking the image failed |

**Developer builds** (`pio run`, version `0.1.0-dev` unless `INKFRAME_FW_VERSION` says
otherwise) never update by themselves. The console's `ota` command checks now, ignores the
rollout, and takes `--feed` for a test feed, which may use plain `http://`. Don't open the
serial port during a trial: that resets the frame, and the bootloader goes back.

## Releasing

1. Choose a version higher than the last release, and tag it: `git tag fw-v0.2.0 && git push origin fw-v0.2.0`.
2. The Firmware workflow (`.github/workflows/firmware.yml`) runs the tests, builds
   `env:release` with that version, signs it with the secret `FW_SIGNING_KEY`, and creates
   the GitHub release with `reterminal-e1002-manifest.json` and `reterminal-e1002-<version>.bin`.
   It then starts the Pages workflow, which puts the release in the feed.
3. **Staged rollout:** Actions → Firmware → Run workflow, with the tag, a rollout
   percentage and a battery minimum. It builds and signs that version again with the new
   numbers and replaces the release's files. `0` pauses a rollout. Frames that already
   have the version aren't affected.
4. **A bad release:** release a higher version with the fix. Frames never go back to a
   lower version, so republishing an older one does nothing.

A new frame gets its first firmware over USB:
`INKFRAME_FW_VERSION=<the latest release> pio run -e release -t upload` (from `firmware/`).

## The signing key

ECDSA P-256 (built into the ESP32's mbedTLS, so the frame needs no extra code).
`deno run --allow-read --allow-write tools/firmware/release.ts keygen` made the key pair on
2026-10-04:

- **The private key** is in `firmware/fw-signing-key.pem` on the developer's Mac
  (gitignored, never printed) and in the GitHub Actions secret `FW_SIGNING_KEY`. Keep an
  offline copy too: without it, frames can only be updated over USB.
- **The public key** is compiled into the firmware: `firmware/src/net/ota_keys.h`.

To replace the key: make a new pair and list the new public key next to the old one, then
release a firmware with both, signed with the old key. Sign later releases with the new
key, and drop the old one from the list once every frame has a firmware that knows the new one.

## Trying it (PLAN.md §12.3)

A test feed served from the Mac, with the developer build on a frame over USB:

```sh
cd firmware
INKFRAME_FW_VERSION=0.1.1 pio run && cp .pio/build/reterminal_e1002/firmware.bin /tmp/0.1.1.bin
cd .. && deno run --allow-read --allow-write --allow-env tools/firmware/release.ts sign \
  --bin /tmp/0.1.1.bin --version 0.1.1 --out /tmp/feed --url-base http://<mac-ip>:8765
python3 -m http.server 8765 --directory /tmp/feed &
firmware/tools/console.py ota --feed http://<mac-ip>:8765   # with PlatformIO's Python
```

`INKFRAME_TEST_CRASH` (e.g. `PLATFORMIO_BUILD_FLAGS=-DINKFRAME_TEST_CRASH`) makes a
firmware that crashes as it starts, to try the rollback.
