# Ink Frame firmware

For the Seeed reTerminal E1002 (ESP32-S3, 7.3" Spectra 6 e-paper, microSD). Plan:
PLAN.md §9; the server side: `shared/api/openapi.yaml` (`device-api`); pairing:
`docs/pairing.md`.

The frame shows photos, checks for new ones and follows its settings (4a), and is set up
from the app over Bluetooth (4b; docs/pairing.md). Updates over the air come in 4c.

## Build, flash, test

From `firmware/`, with the E1002 on USB-C and its power switch on:

```sh
pio run                      # build
pio run -t upload            # build and flash (about 40 s)
pio device monitor           # logs (115200)
pio test -e native           # unit tests on the computer (schedule, photo list)
```

## Set it up

From the app: **Connect the frame**. A new frame (or one whose green button was held for
3 s) shows its name, its 4 characters and a 6-digit code, and advertises over Bluetooth
for 10 minutes; the phone asks for the code. A frame still linked to another album is
refused until a factory reset (green button 10 s).

### Over USB (developer builds)

The serial console is compiled in while `INKFRAME_CONSOLE` is 1 (the default here; release
builds will set it to 0, 4c). In setup it runs alongside Bluetooth. Opening the serial
port resets the frame, which then listens for a command for 1.5 s.
`tools/console.py` does that. Run it with PlatformIO's Python, which has pyserial:

```sh
PY=$(pio system info --json-output | python3 -c 'import json,sys; print(json.load(sys.stdin)["python_exe"]["value"])')
$PY tools/console.py info          # the frame and its memory card
$PY tools/console.py wifi_scan     # networks it can see (2.4 GHz)
$PY tools/console.py provision --ssid Home --api-base-url https://<ref>.supabase.co/functions/v1 --pairing-token <token> [--erase-sd]
$PY tools/console.py sync [--full] | erase_sd | reset
$PY tools/console.py log 30        # just the logs, for 30 s after a reset
$PY tools/console.py show picture.png [--minutes 30]   # draw an 800×480 PNG as it is, then sleep (tools/calibration)
```

`provision` asks for the Wi-Fi password (or reads `WIFI_PASSWORD`). For a pairing token:
the app's **Connect the frame → Connect with a code (developer)** in developer mode, or,
for a test album on a throwaway project, from the repo root:

```sh
SUPABASE_PROJECT_REF=<ref> deno run --allow-all tools/dev/usb-connect.ts setup --ssid <wifi> [--photos 3] [--erase-sd]
SUPABASE_PROJECT_REF=<ref> deno run --allow-all tools/dev/usb-connect.ts photos --add 5   # or --clear
SUPABASE_PROJECT_REF=<ref> deno run --allow-all tools/dev/usb-connect.ts remove
```

## On the frame

- **Green button:** press to check for new photos now; hold 3 s to set it up again;
  hold 10 s for a factory reset (Wi-Fi, link and photo cache cleared).
- **White buttons:** the next photo (left: the previous one, when in order).
- **Bottom row:** the battery bar; a short red mark at its left end after a failed check.
- **Screens:** set up (the frame's name, its 4 characters and the Bluetooth code, large;
  without the code once setup times out), Ready (no photos
  yet), not connected to an album (its album was deleted, or the frame was disconnected), no memory card, can't read the memory card.

## Layout (`src/`)

| | |
|---|---|
| `main.cpp` | the boot state machine (PLAN.md §9.4): every wake ends in deep sleep |
| `core/` | pure logic with unit tests: `schedule` (quiet hours, next wake, backoff), `manifest` (photo list, where photos live on the card, what fits, which photo next) |
| `board/` | the E1002's pins; the SPI bus the display and card share |
| `display/` | PNG decoding into a PSRAM frame buffer, photos and screens (GxEPD2) |
| `storage/` | `sd_card` (mount, card states, format), `cache` (photos under `/cache`) |
| `net/` | Wi-Fi and NTP, HTTPS with the built-in CA bundle, the sync and mirror |
| `config/` | what's kept in flash (NVS) |
| `power/` | battery, wake reason, deep sleep |
| `ble/` | Bluetooth for Connect the frame (NimBLE: advertising, LE Secure Connections with the code on screen, the four characteristics) |
| `provision/` | provisioning steps (shared by Bluetooth and the console), the setup loop (`pairing_mode`), the serial console |

## The memory card

- **File systems:** FAT16 and FAT32, any size up to 2 TB. exFAT (how cards over 32 GB
  come) and NTFS aren't readable: the frame says "Can't read the memory card", reports it,
  and the app offers to erase it.
- **Erasing** formats the whole card as FAT32 (FAT16 if it's tiny), from the app at setup
  (`provision.erase_sd`) or the console (`erase_sd`). It takes up to about a minute on big
  cards.
- **No card:** "No memory card" on the frame and in the app; it still checks in.
- **Space:** the frame keeps 8 MB free, deletes photos that are no longer listed first,
  then downloads in list order while they fit; the rest wait for the next check, and the
  app says the photos don't all fit.
- **Other files** on the card are never touched; only erasing removes them.
- **A swapped card** (no `/cache/manifest.txt`): the frame asks for the whole list again.
- **A card that won't mount** after a reset: powered off and on, and retried more slowly.
