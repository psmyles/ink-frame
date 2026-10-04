#include "serial_console.h"

#include <ArduinoJson.h>
#include <SD.h>

#include "display/display.h"
#include "net/sync.h"
#include "net/wifi.h"
#include "power/power.h"
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

// What has arrived of the current line; true once it's complete.
static String s_line;
static bool takeLine(String& line) {
  while (Serial.available()) {
    const char c = static_cast<char>(Serial.read());
    if (c == '\n') {
      line = s_line;
      s_line = "";
      return true;
    }
    if (c != '\r') s_line += c;
    if (s_line.length() > kMaxLine) s_line = "";  // too long: dropped, like a bad message
  }
  return false;
}

static bool readLine(String& line, uint32_t deadline) {
  while (millis() < deadline) {
    if (takeLine(line)) return true;
    delay(5);
  }
  return false;
}

// A PNG from the computer, straight onto the screen (tools/calibration): the frame's
// palette colours are drawn as they are, anything else as the nearest of them.
static void show(size_t bytes) {
  JsonDocument d;
  uint8_t* buf = bytes > 0 && bytes <= 4 * 1024 * 1024 ? static_cast<uint8_t*>(ps_malloc(bytes)) : nullptr;
  if (!buf || card::state() != CardState::ok) {
    free(buf);
    d["shown"] = false;
    d["error"] = buf ? "no_card" : "bad_size";
    reply(d);
    return;
  }
  JsonDocument ready;
  ready["ready"] = true;
  reply(ready);
  size_t got = 0;
  uint32_t last = millis();
  while (got < bytes && millis() - last < 5000) {
    const size_t n = Serial.read(buf + got, bytes - got);
    if (n > 0) {
      got += n;
      last = millis();
    } else {
      delay(1);
    }
  }
  bool ok = false;
  if (got == bytes) {
    static const char* kPath = "/show.png";
    File f = SD.open(kPath, FILE_WRITE);
    ok = f && f.write(buf, bytes) == bytes;
    if (f) f.close();
    ok = ok && display::decodePhoto(kPath);
    SD.remove(kPath);
  }
  free(buf);
  if (ok) {
    card::unmount();  // the display has the bus to itself while it refreshes
    display::showPhoto(-1, false);
    card::mount();
  }
  d["shown"] = ok;
  if (!ok) d["error"] = got == bytes ? "bad_png" : "timeout";
  reply(d);
}

void factoryReset(Config& cfg) {
  if (card::state() == CardState::ok) cache::wipe();
  nvs::eraseAll();
  cfg = nvs::load();
  display::forgetShown();
}

// One command line. `none` for an empty line.
static Outcome handle(Config& cfg, String line, int batteryPct) {
  line.trim();
  if (line.isEmpty()) return Outcome::none;
  JsonDocument req;
  if (deserializeJson(req, line) != DeserializationError::Ok) {
    replyError("bad_request");
    return Outcome::leave;  // something arrived: keep listening
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
    return Outcome::reset;
  } else if (cmd == "show") {
    show(req["bytes"] | 0);
  } else if (cmd == "sleep") {
    JsonDocument d;
    d["sleeping"] = true;
    reply(d);
    power::deepSleep(max(1, req["minutes"] | 30) * 60);
  } else if (cmd == "run") {
    return Outcome::run;
  } else {
    replyError("bad_request");
  }
  return Outcome::leave;
}

Outcome run(Config& cfg, uint32_t waitMs, uint32_t idleMs, int batteryPct) {
  uint32_t deadline = millis() + waitMs;
  Outcome outcome = Outcome::none;
  String line;
  while (readLine(line, deadline)) {
    const Outcome o = handle(cfg, line, batteryPct);
    if (o == Outcome::none) continue;
    deadline = millis() + idleMs;
    if (o == Outcome::reset) outcome = Outcome::reset;
    if (o == Outcome::provisioned) return o;
    if (o == Outcome::run) return outcome == Outcome::reset ? outcome : o;
  }
  return outcome;
}

Outcome poll(Config& cfg, int batteryPct) {
  String line;
  return takeLine(line) ? handle(cfg, line, batteryPct) : Outcome::none;
}

}  // namespace console
