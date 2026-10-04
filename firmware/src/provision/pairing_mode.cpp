#include "pairing_mode.h"

#include <esp_random.h>

#include <string>

#include "ble/ble_link.h"
#include "display/display.h"
#include "net/wifi.h"
#include "provision/provisioning.h"
#include "provision/serial_console.h"
#include "util/log.h"

#ifndef INKFRAME_CONSOLE
#define INKFRAME_CONSOLE 1
#endif

namespace pairing {

static const uint32_t kIdleMs = 10 * 60000;  // advertising without a connection
static const uint32_t kMaxMs = 30 * 60000;   // even with the app connected

static std::string infoJson(const Config& cfg) {
  JsonDocument d;
  provisioning::info(cfg, d);
  std::string s;
  serializeJson(d, s);
  return s;
}

static void status(const JsonDocument& d) { ble::notifyStatus(d); }

// One message from the app. True once linked.
static bool handle(Config& cfg, ble::Channel channel, const std::string& line, int battery) {
  JsonDocument req;
  if (line.empty() || deserializeJson(req, line) != DeserializationError::Ok || !req.is<JsonObject>()) {
    JsonDocument d;
    d["state"] = "error";
    d["code"] = "bad_request";
    ble::notifyStatus(d);
    return false;
  }
  if (channel == ble::Channel::wifiScan) {
    if (!(req["scan"] | false)) return false;
    for (const auto& n : wifi::scan()) {
      JsonDocument d;
      d["ssid"] = n.ssid;
      d["rssi"] = n.rssi;
      d["secure"] = n.secure;
      ble::notifyWifiScan(d);
    }
    wifi::off();
    JsonDocument done;
    done["done"] = true;
    ble::notifyWifiScan(done);
    return false;
  }
  LOGLN("ble: provision");
  const bool linked = provisioning::provision(cfg, req.as<JsonVariantConst>(), battery, status);
  ble::setInfo(infoJson(cfg));  // the card may have been erased, the link made
  return linked;
}

bool run(Config& cfg, int battery) {
  const uint32_t passkey = esp_random() % 1000000;
  const String name = provisioning::name();
  LOGF("setup: %s\n", name.c_str());
  ble::start(name.c_str(), passkey, infoJson(cfg));
  // Already advertising: a phone can connect while the screen refreshes (~20 s).
  display::showSetup(provisioning::suffix(), name, passkey);

  const uint32_t started = millis();
  uint32_t lastActivity = started;
  bool linked = false;
  while (!linked) {
    const uint32_t t = millis();
    if (ble::connected()) lastActivity = t;
    if (t - started > kMaxMs || t - lastActivity > kIdleMs) break;
    ble::Channel channel;
    std::string line;
    if (ble::nextRequest(channel, line)) {
      linked = handle(cfg, channel, line, battery);
      lastActivity = millis();
    }
#if INKFRAME_CONSOLE
    const console::Outcome o = console::poll(cfg, battery);
    if (o != console::Outcome::none) {
      lastActivity = millis();
      if (o == console::Outcome::provisioned) linked = true;
      ble::setInfo(infoJson(cfg));
    }
#endif
    delay(10);
  }
  if (linked) delay(2000);  // `ready` reaches the app before the link goes
  ble::stop();
  LOGF("setup: %s\n", linked ? "linked" : "timed out");
  // The code is gone: don't leave it on the screen.
  if (!linked) display::showSetupAsleep(provisioning::suffix(), name);
  return linked;
}

}  // namespace pairing
