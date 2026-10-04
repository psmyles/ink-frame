// The serial console: developer builds only (INKFRAME_CONSOLE; Bluetooth is how a frame
// is set up, PLAN.md §16). One JSON object per line in, replies as "@ <json>" lines
// between the logs. Commands:
//   {"cmd":"info"}                       → info (docs/pairing.md)
//   {"cmd":"wifi_scan"}                  → one line per network, then {"done":true}
//   {"cmd":"provision", "ssid":…, "password":…, "api_base_url":…, "pairing_token":…,
//    "erase_sd":false}                   → status lines, as over Bluetooth
//   {"cmd":"sync"}                       → a check for new photos
//   {"cmd":"erase_sd"}                   → formats the memory card
//   {"cmd":"reset"}                      → factory reset
//   {"cmd":"show","bytes":N}             → "ready", then N raw bytes of a PNG, drawn as is
//                                          (no battery bar; the photo list is untouched)
//   {"cmd":"sleep","minutes":M}          → deep sleep, keeping what's on the screen
//   {"cmd":"run"}                        → leave the console, carry on as usual
#pragma once
#include <Arduino.h>

#include "config/nvs_settings.h"

namespace console {

// none: nothing arrived; leave: a command was handled; run: "run" (carry on as usual);
// provisioned: linked; reset: factory reset.
enum class Outcome : uint8_t { none, leave, run, provisioned, reset };

// Waits up to waitMs for a first command; once one arrives, keeps going until "run",
// a successful provision, or idleMs without a command.
Outcome run(Config& cfg, uint32_t waitMs, uint32_t idleMs, int batteryPct);

// For a loop that also does other work (setup mode): reads what has arrived without
// waiting, and handles a command once its line is complete.
Outcome poll(Config& cfg, int batteryPct);

// Clears the link, Wi-Fi, settings and the photo cache (the green button held 10 s).
void factoryReset(Config& cfg);

}  // namespace console
