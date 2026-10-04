// The serial console (Phase 4a; Bluetooth replaces it for provisioning in 4b). One JSON
// object per line in, replies as "@ <json>" lines between the logs. Commands:
//   {"cmd":"info"}                       → info (docs/pairing.md)
//   {"cmd":"wifi_scan"}                  → one line per network, then {"done":true}
//   {"cmd":"provision", "ssid":…, "password":…, "api_base_url":…, "pairing_token":…,
//    "erase_sd":false}                   → status lines, as over Bluetooth
//   {"cmd":"sync"}                       → a check for new photos
//   {"cmd":"erase_sd"}                   → formats the memory card
//   {"cmd":"reset"}                      → factory reset
//   {"cmd":"run"}                        → leave the console, carry on as usual
#pragma once
#include <Arduino.h>

#include "config/nvs_settings.h"

namespace console {

enum class Outcome : uint8_t { none, provisioned, leave, reset };

// Waits up to waitMs for a first command; once one arrives, keeps going until "run",
// a successful provision, or idleMs without a command.
Outcome run(Config& cfg, uint32_t waitMs, uint32_t idleMs, int batteryPct);

// Clears the link, Wi-Fi, settings and the photo cache (the green button held 10 s).
void factoryReset(Config& cfg);

}  // namespace console
