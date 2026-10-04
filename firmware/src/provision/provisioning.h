// Connecting the frame to a frame project (docs/pairing.md): the same messages over any
// transport. 4a: the serial console; 4b: Bluetooth.
#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>

#include <functional>

#include "config/nvs_settings.h"

namespace provisioning {

// "e1002-<base MAC>", and its last 4 hex digits upper case (the frame's name: InkFrame-XXXX).
String hwId();
String suffix();
String name();

// `info`: hw_id, model_id, fw_version, frame_id, sd.
void info(const Config& cfg, JsonDocument& out);

// Each `status` message, e.g. {"state":"wifi_connecting"}.
using StatusSink = std::function<void(const JsonDocument&)>;

// `provision`: optionally erase the card, join Wi-Fi, claim, first check. Returns true
// once linked (`ready`); on failure the frame stays in setup for another try.
bool provision(Config& cfg, JsonVariantConst request, int batteryPct, const StatusSink& status);

}  // namespace provisioning
