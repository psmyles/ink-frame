#include "serial_console.h"

#include <ArduinoJson.h>

#include "display/display.h"
#include "net/sync.h"
#include "net/wifi.h"
#include "provision/provisioning.h"
#include "storage/cache.h"
#include "storage/sd_card.h"
#include "util/log.h"

namespace console {

static const size_t kMaxLine = 1024;  // as over Bluetooth (shared/pairing.json)

static void reply(const JsonDocument& d) {
  Serial.print("@ ");
  serializeJson(d, Serial);
  Serial.println();
}

static void replyError(const char* code) {
  JsonDocument d;
  d["state"] = "error";
  d["code"] = code;
  reply(d);
}

static bool readLine(String& line, uint32_t deadline) {
  line = "";
  while (millis() < deadline) {
    while (Serial.available()) {
      const char c = static_cast<char>(Serial.read());
      if (c == '\n') return true;
      if (c != '\r') line += c;
      if (line.length() > kMaxLine) line = "";  // too long: dropped, like a bad message
    }
    delay(5);
  }
  return false;
}

void factoryReset(Config& cfg) {
  if (card::state() == CardState::ok) cache::wipe();
  nvs::eraseAll();
  cfg = nvs::load();
  display::forgetShown();
}

Outcome run(Config& cfg, uint32_t waitMs, uint32_t idleMs, int batteryPct) {
  uint32_t deadline = millis() + waitMs;
  Outcome outcome = Outcome::none;
  String line;
  while (readLine(line, deadline)) {
    line.trim();
    if (line.isEmpty()) continue;
    deadline = millis() + idleMs;
    JsonDocument req;
    if (deserializeJson(req, line) != DeserializationError::Ok) {
      replyError("bad_request");
      continue;
    }
    const String cmd = req["cmd"] | "";
    LOGF("console: %s\n", cmd.c_str());
    if (cmd == "info") {
      JsonDocument d;
      provisioning::info(cfg, d);
      reply(d);
    } else if (cmd == "wifi_scan") {
      for (const auto& n : wifi::scan()) {
        JsonDocument d;
        d["ssid"] = n.ssid;
        d["rssi"] = n.rssi;
        d["secure"] = n.secure;
        reply(d);
      }
      wifi::off();
      JsonDocument done;
      done["done"] = true;
      reply(done);
    } else if (cmd == "provision") {
      if (provisioning::provision(cfg, req.as<JsonVariantConst>(), batteryPct, reply)) return Outcome::provisioned;
    } else if (cmd == "sync") {
      JsonDocument d;
      if (!cfg.linked()) {
        d["sync"] = "not_linked";
      } else if (wifi::connect(cfg.ssid, cfg.password) != wifi::Join::ok) {
        d["sync"] = "no_wifi";
      } else {
        photos::Report r;
        const photos::Result s = photos::sync(cfg, batteryPct, req["full"] | false, r);
        wifi::off();
        d["sync"] = s == photos::Result::ok ? "ok" : (s == photos::Result::removed ? "removed" : "failed");
        d["total"] = r.total;
        d["added"] = r.added;
        d["deleted"] = r.deleted;
        d["skipped"] = r.skipped;
        d["failed"] = r.failed;
      }
      reply(d);
    } else if (cmd == "erase_sd") {
      JsonDocument d;
      d["erased"] = card::format();
      display::forgetShown();
      reply(d);
    } else if (cmd == "reset") {
      factoryReset(cfg);
      JsonDocument d;
      d["reset"] = true;
      reply(d);
      outcome = Outcome::reset;
    } else if (cmd == "run") {
      return Outcome::leave;
    } else {
      replyError("bad_request");
    }
  }
  return outcome;
}

}  // namespace console
