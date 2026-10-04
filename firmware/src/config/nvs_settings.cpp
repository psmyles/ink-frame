#include "nvs_settings.h"

#include <Preferences.h>

static const char* kNs = "inkframe";

// getString logs an error for a key that isn't there (every key, on a new frame).
static String str(Preferences& p, const char* key, const char* fallback = "") {
  return p.isKey(key) ? p.getString(key, fallback) : String(fallback);
}

namespace nvs {

Config load() {
  Preferences p;
  Config c;
  if (!p.begin(kNs, false)) return c;  // read-write: creates the namespace on a new frame
  c.ssid = str(p, "ssid");
  c.password = str(p, "pass");
  c.apiBaseUrl = str(p, "api");
  c.deviceSecret = str(p, "secret");
  c.frameId = str(p, "frame");
  c.manifestVersion = p.getLong64("mver", 0);
  c.lastSyncAt = p.getLong64("synced", 0);
  c.settings.schedule.imageIntervalS = p.getUInt("img_s", 14400);
  c.settings.schedule.syncIntervalS = p.getUInt("sync_s", 86400);
  c.settings.schedule.quietStart = p.getInt("q_start", -1);
  c.settings.schedule.quietEnd = p.getInt("q_end", -1);
  c.settings.sequential = p.getBool("seq", false);
  c.settings.tzPosix = str(p, "tz", "UTC0");
  p.end();
  return c;
}

void saveWifi(const String& ssid, const String& password) {
  Preferences p;
  p.begin(kNs, false);
  p.putString("ssid", ssid);
  p.putString("pass", password);
  p.end();
}

void saveLink(const String& apiBaseUrl, const String& deviceSecret, const String& frameId) {
  Preferences p;
  p.begin(kNs, false);
  if (str(p, "frame") != frameId) {
    // Another frame: its photo list starts from scratch.
    p.putLong64("mver", 0);
    p.putLong64("synced", 0);
  }
  p.putString("api", apiBaseUrl);
  p.putString("secret", deviceSecret);
  p.putString("frame", frameId);
  p.end();
}

void saveSync(int64_t manifestVersion, int64_t lastSyncAt, const FrameSettings& s) {
  Preferences p;
  p.begin(kNs, false);
  p.putLong64("mver", manifestVersion);
  p.putLong64("synced", lastSyncAt);
  p.putUInt("img_s", s.schedule.imageIntervalS);
  p.putUInt("sync_s", s.schedule.syncIntervalS);
  p.putInt("q_start", s.schedule.quietStart);
  p.putInt("q_end", s.schedule.quietEnd);
  p.putBool("seq", s.sequential);
  p.putString("tz", s.tzPosix);
  p.end();
}

void forgetLink() {
  Preferences p;
  p.begin(kNs, false);
  for (const char* k : {"api", "secret", "frame", "mver", "synced", "img_s", "sync_s", "q_start", "q_end", "seq", "tz"}) {
    p.remove(k);
  }
  p.end();
}

void eraseAll() {
  Preferences p;
  p.begin(kNs, false);
  p.clear();
  p.end();
}

}  // namespace nvs
