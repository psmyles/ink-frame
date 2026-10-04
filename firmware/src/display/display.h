// The e-paper: photos and the frame's own screens (PLAN.md §9.1–9.2). A full refresh
// takes ~20 s on the Spectra 6 panel, so the same screen is never drawn twice in a row.
#pragma once
#include <Arduino.h>

namespace display {

// Decodes a PNG from the card into the PSRAM frame buffer (the card must be mounted).
bool decodePhoto(const char* path);
// Draws the decoded photo, with the battery bar along the bottom and, after a failed
// check, a small red mark at its left end.
void showPhoto(int batteryPct, bool checkFailed);

// The frame's own screens. Each is drawn only if it isn't already showing.
// Setup (PAIRING): the name, its 4 characters and the Bluetooth code, large.
void showSetup(const String& suffix, const String& name, uint32_t passkey);
// After setup timed out: no code (it's no longer valid), how to start again.
void showSetupAsleep(const String& suffix, const String& name);
void showReady();
void showRemoved();
void showNoCard();
void showCardUnreadable();
void showError(const char* line1, const char* line2);

// Before deep sleep.
void sleep();

// Forget what's showing (after a factory reset, a new photo list).
void forgetShown();

}  // namespace display
