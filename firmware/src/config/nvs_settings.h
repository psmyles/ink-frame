// What the frame keeps in flash (NVS, PLAN.md §9.3): Wi-Fi, its link to a frame, the
// settings from the last check, and when that was.
#pragma once
#include <Arduino.h>

#include "core/schedule.h"

struct FrameSettings {
  schedule::Settings schedule;
  bool sequential = false;
  String tzPosix = "UTC0";
};

struct Config {
  String ssid, password;
  String apiBaseUrl;    // https://<ref>.supabase.co/functions/v1
  String deviceSecret;  // from /device-api/claim
  String frameId;
  int64_t manifestVersion = 0;
  int64_t lastSyncAt = 0;  // Unix seconds of the last successful check
  FrameSettings settings;

  bool linked() const { return deviceSecret.length() > 0 && apiBaseUrl.length() > 0; }
  bool hasWifi() const { return ssid.length() > 0; }
};

namespace nvs {
Config load();
void saveWifi(const String& ssid, const String& password);
void saveLink(const String& apiBaseUrl, const String& deviceSecret, const String& frameId);
void saveSync(int64_t manifestVersion, int64_t lastSyncAt, const FrameSettings& s);
// 410 from the server: forget the link and the settings, keep Wi-Fi.
void forgetLink();
// Green button held 10 s: everything.
void eraseAll();
}  // namespace nvs
