#include "wifi.h"

#include <WiFi.h>
#include <sys/time.h>
#include <time.h>

#include "util/log.h"

namespace wifi {

static volatile uint8_t s_lastReason = 0;

const char* joinReason(Join j) {
  switch (j) {
    case Join::auth:
      return "auth";
    case Join::notFound:
      return "not_found";
    default:
      return "other";
  }
}

Join connect(const String& ssid, const String& password, uint32_t timeoutMs) {
  WiFi.persistent(false);
  WiFi.mode(WIFI_STA);
  s_lastReason = 0;
  static bool hooked = false;
  if (!hooked) {
    WiFi.onEvent([](WiFiEvent_t, WiFiEventInfo_t info) { s_lastReason = info.wifi_sta_disconnected.reason; },
                 ARDUINO_EVENT_WIFI_STA_DISCONNECTED);
    hooked = true;
  }
  WiFi.begin(ssid.c_str(), password.length() ? password.c_str() : nullptr);
  const uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < timeoutMs) {
    // A wrong password or a missing network won't fix itself: stop early.
    const uint8_t r = s_lastReason;
    if (r == WIFI_REASON_AUTH_FAIL || r == WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT || r == WIFI_REASON_HANDSHAKE_TIMEOUT ||
        r == WIFI_REASON_NO_AP_FOUND) {
      if (millis() - t0 > 4000) break;
    }
    delay(100);
  }
  if (WiFi.status() == WL_CONNECTED) {
    LOGF("wifi: joined %s (%d dBm)\n", ssid.c_str(), WiFi.RSSI());
    return Join::ok;
  }
  const uint8_t r = s_lastReason;
  LOGF("wifi: couldn't join %s (reason %u)\n", ssid.c_str(), r);
  off();
  if (r == WIFI_REASON_AUTH_FAIL || r == WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT || r == WIFI_REASON_HANDSHAKE_TIMEOUT ||
      r == WIFI_REASON_AUTH_EXPIRE) {
    return Join::auth;
  }
  if (r == WIFI_REASON_NO_AP_FOUND) return Join::notFound;
  return Join::other;
}

void off() {
  WiFi.disconnect(true);
  WiFi.mode(WIFI_OFF);
}

int rssi() { return WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : 0; }

std::vector<Network> scan() {
  WiFi.mode(WIFI_STA);
  const int n = WiFi.scanNetworks(false, false);
  std::vector<Network> out;
  for (int i = 0; i < n; i++) {
    const String ssid = WiFi.SSID(i);
    if (ssid.isEmpty()) continue;
    bool seen = false;
    for (auto& o : out) {
      if (o.ssid == ssid) {
        if (WiFi.RSSI(i) > o.rssi) o.rssi = WiFi.RSSI(i);
        seen = true;
      }
    }
    if (!seen) out.push_back({ssid, WiFi.RSSI(i), WiFi.encryptionType(i) != WIFI_AUTH_OPEN});
  }
  WiFi.scanDelete();
  std::sort(out.begin(), out.end(), [](const Network& a, const Network& b) { return a.rssi > b.rssi; });
  if (out.size() > 20) out.resize(20);
  return out;
}

bool timeKnown() { return time(nullptr) > 1704067200; }  // after 2024-01-01

bool syncTime(const String& tzPosix, int64_t serverTime) {
  configTzTime(tzPosix.c_str(), "pool.ntp.org", "time.google.com", "time.cloudflare.com");
  const uint32_t t0 = millis();
  while (!timeKnown() && millis() - t0 < 8000) delay(100);
  if (!timeKnown() && serverTime > 0) {
    timeval tv{static_cast<time_t>(serverTime), 0};
    settimeofday(&tv, nullptr);
  }
  return timeKnown();
}

}  // namespace wifi
