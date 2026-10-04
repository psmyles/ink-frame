// Firmware updates (PLAN.md §10, docs/ota.md). After a check for new photos the frame
// reads <feed>/<model>/manifest.json, checks its signature against the keys compiled in
// (ota_keys.h), and installs a newer release into the other app slot, checking its size
// and SHA-256. The new firmware's first start (a "trial") checks for photos at once and
// keeps itself only if that works; if it fails, crashes or hangs, the bootloader goes
// back to the previous firmware. A version that failed twice here isn't tried again.
#pragma once
#include <Arduino.h>

#include "core/firmware_update.h"

#ifndef FIRMWARE_FEED_URL
#define FIRMWARE_FEED_URL "https://psmyles.github.io/ink-frame/firmware"
#endif

namespace ota {

struct Result {
  bool installed = false;  // restart to run it
  String status;           // fwupdate::toString(decision), or what went wrong (docs/ota.md)
  String version;          // the feed's version, if it was read
};

// Wi-Fi must be on. anyRollout: install even outside the rollout (the console's `ota`).
// http:// feeds and images only in developer builds (INKFRAME_CONSOLE).
Result check(const String& feedUrl, int batteryPct, bool anyRollout = false);

// The automatic check runs at most every 20 hours (and on a press of the green button).
bool due(int64_t now);
void markChecked(int64_t now);

// This start is a new firmware's trial (it hasn't kept itself yet). Starts a 5-minute
// watchdog: a trial that hangs restarts, and the bootloader goes back.
bool beginTrial();
// The trial worked: keep this firmware.
void keep();
// The trial failed: back to the previous firmware.
[[noreturn]] void giveUp();

}  // namespace ota
