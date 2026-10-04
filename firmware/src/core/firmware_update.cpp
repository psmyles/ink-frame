#include "firmware_update.h"

#include <stdio.h>

namespace fwupdate {

std::string signedText(const Release& r) {
  return "inkframe-firmware 1\n"
         "model " + r.modelId + "\n"
         "version " + r.version + "\n"
         "url " + r.url + "\n"
         "size " + std::to_string(r.size) + "\n"
         "sha256 " + r.sha256 + "\n"
         "min_battery_pct " + std::to_string(r.minBatteryPct) + "\n"
         "rollout_percent " + std::to_string(r.rolloutPercent) + "\n";
}

static bool parse(const std::string& v, long out[3]) {
  char rest;
  return sscanf(v.c_str(), "%ld.%ld.%ld%c", &out[0], &out[1], &out[2], &rest) >= 3 && out[0] >= 0 && out[1] >= 0 &&
         out[2] >= 0;
}

int compareVersions(const std::string& a, const std::string& b) {
  long x[3], y[3];
  const bool okA = parse(a, x), okB = parse(b, y);
  if (!okA || !okB) return okA - okB;
  for (int i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] < y[i] ? -1 : 1;
  }
  return 0;
}

int rolloutBucket(const std::string& hwId) {
  uint32_t h = 2166136261u;  // FNV-1a
  for (unsigned char c : hwId) h = (h ^ c) * 16777619u;
  return static_cast<int>(h % 100);
}

Decision decide(const Release& r, const std::string& runningVersion, const std::string& modelId, const std::string& hwId,
                int batteryPct, int failedTries, bool ignoreRollout) {
  if (r.modelId != modelId) return Decision::otherModel;
  if (compareVersions(r.version, runningVersion) <= 0) return Decision::upToDate;
  if (failedTries >= kMaxTries) return Decision::gaveUp;
  if (!ignoreRollout && rolloutBucket(hwId) >= r.rolloutPercent) return Decision::notYet;
  if (batteryPct < r.minBatteryPct) return Decision::lowBattery;
  return Decision::install;
}

const char* toString(Decision d) {
  switch (d) {
    case Decision::install: return "install";
    case Decision::upToDate: return "up_to_date";
    case Decision::otherModel: return "other_model";
    case Decision::notYet: return "not_yet";
    case Decision::lowBattery: return "low_battery";
    case Decision::gaveUp: return "gave_up";
  }
  return "?";
}

}  // namespace fwupdate
