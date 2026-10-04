#include "provisioning.h"

#include <esp_mac.h>

#include <vector>

#include "core/manifest.h"
#include "display/display.h"
#include "net/api_client.h"
#include "net/sync.h"
#include "net/wifi.h"
#include "storage/cache.h"
#include "storage/sd_card.h"
#include "util/log.h"

namespace provisioning {

String hwId() {
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char s[24];
  snprintf(s, sizeof s, "e1002-%02x%02x%02x%02x%02x%02x", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  return String(s);
}

String suffix() {
  String id = hwId();
  id = id.substring(id.length() - 4);
  id.toUpperCase();
  return id;
}

String name() { return "InkFrame-" + suffix(); }

void info(const Config& cfg, JsonDocument& out) {
  out["hw_id"] = hwId();
  out["model_id"] = MODEL_ID;
  out["fw_version"] = FW_VERSION;
  if (cfg.frameId.length()) {
    out["frame_id"] = cfg.frameId;
  } else {
    out["frame_id"] = nullptr;
  }
  JsonObject sd = out["sd"].to<JsonObject>();
  const CardState st = card::state();
  sd["state"] = card::stateName(st);
  if (st == CardState::ok) {
    std::vector<manifest::Image> cached;
    cache::loadManifest(cached);
    uint64_t cacheBytes = 0;
    for (const auto& i : cached) cacheBytes += i.bytes;
    const uint64_t total = card::totalBytes(), free = card::freeBytes();
    const uint64_t used = total - free;
    sd["total_bytes"] = total;
    sd["free_bytes"] = free;
    sd["cache_bytes"] = cacheBytes;
    sd["other_bytes"] = used > cacheBytes ? used - cacheBytes : 0;
  }
}

static void say(const StatusSink& status, const char* state, const char* key = nullptr, const String& value = "") {
  JsonDocument d;
  d["state"] = state;
  if (key) d[key] = value;
  status(d);
}

static void fail(const StatusSink& status, const char* code) { say(status, "error", "code", code); }

bool provision(Config& cfg, JsonVariantConst req, int batteryPct, const StatusSink& status) {
  const String ssid = req["ssid"] | "";
  const String password = req["password"] | "";
  String api = req["api_base_url"] | "";
  const String token = req["pairing_token"] | "";
  while (api.endsWith("/")) api.remove(api.length() - 1);
  if (ssid.isEmpty() || !api.startsWith("https://") || token.isEmpty()) {
    fail(status, "bad_request");
    return false;
  }
  // Linked to another frame: only a 10-second reset frees it (docs/pairing.md).
  if (cfg.linked() && cfg.apiBaseUrl != api) {
    fail(status, "linked_elsewhere");
    return false;
  }

  if (req["erase_sd"] | false) {
    say(status, "erasing");
    if (!card::format()) {
      fail(status, "sd_failed");
      return false;
    }
    display::forgetShown();
  }

  say(status, "wifi_connecting");
  const wifi::Join j = wifi::connect(ssid, password);
  if (j != wifi::Join::ok) {
    say(status, "wifi_failed", "reason", wifi::joinReason(j));
    return false;
  }
  nvs::saveWifi(ssid, password);
  cfg.ssid = ssid;
  cfg.password = password;
  if (!wifi::syncTime(cfg.settings.tzPosix)) LOGLN("provision: no NTP yet");

  say(status, "claiming");
  JsonDocument body;
  body["pairing_token"] = token;
  body["hw_id"] = hwId();
  body["model_id"] = MODEL_ID;
  body["fw_version"] = FW_VERSION;
  JsonDocument res;
  const api::Response r = api::postJson(api + "/device-api/claim", body, "", res);
  if (r.status != 200) {
    wifi::off();
    if (r.status == 0) {
      fail(status, "unreachable");
    } else if (r.errorCode == "invalid_pairing_token" || r.errorCode == "model_mismatch" ||
               r.errorCode == "unknown_model") {
      fail(status, r.errorCode.c_str());
    } else {
      fail(status, "server");
    }
    return false;
  }
  const String frameId = res["frame_id"] | "";
  const String secret = res["device_secret"] | "";
  if (frameId != cfg.frameId && card::state() == CardState::ok) cache::wipe();  // another frame's photos
  nvs::saveLink(api, secret, frameId);
  cfg = nvs::load();
  say(status, "claimed", "frame_id", frameId);

  say(status, "syncing");
  photos::Report report;
  const photos::Result s = photos::sync(cfg, batteryPct, true, report);
  wifi::off();
  if (s == photos::Result::removed) {
    fail(status, "server");
    return false;
  }
  // A failed first check still leaves the frame linked: it gets its photos on its own.
  say(status, "ready");
  return true;
}

}  // namespace provisioning
