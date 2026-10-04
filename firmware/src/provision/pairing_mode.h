// Setup (PAIRING, docs/pairing.md): a new Bluetooth code on the screen, advertising for
// 10 minutes (kept up while the app is connected), and the serial console in developer
// builds (INKFRAME_CONSOLE).
#pragma once
#include "config/nvs_settings.h"

namespace pairing {

// True once linked (the app's `provision` reached `ready`); false if nobody connected
// the frame in time.
bool run(Config& cfg, int batteryPct);

}  // namespace pairing
