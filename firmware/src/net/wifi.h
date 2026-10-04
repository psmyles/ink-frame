// Wi-Fi: joining (with the reason it failed, docs/pairing.md `wifi_failed`), scanning,
// and the time (NTP).
#pragma once
#include <Arduino.h>

#include <vector>

namespace wifi {

enum class Join : uint8_t { ok, auth, notFound, other };
const char* joinReason(Join j);  // "auth", "not_found", "other"

Join connect(const String& ssid, const String& password, uint32_t timeoutMs = 15000);
void off();
int rssi();

struct Network {
  String ssid;
  int rssi;
  bool secure;
};
// 2.4 GHz networks, strongest first, hidden ones left out, each name once, at most 20.
std::vector<Network> scan();

// Sets the clock from NTP in the given POSIX time zone; serverTime (Unix seconds) is
// the fallback. Returns whether the clock is now right.
bool syncTime(const String& tzPosix, int64_t serverTime = 0);
bool timeKnown();

}  // namespace wifi
