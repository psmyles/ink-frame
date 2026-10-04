// Firmware updates from the central feed (PLAN.md §10, docs/ota.md): what a release
// says, the text its signature covers, and whether this frame should install it.
// Pure logic: no Arduino, tested on the computer (test/test_firmware_update).
#pragma once
#include <stdint.h>

#include <string>

namespace fwupdate {

// <feed>/<model_id>/manifest.json
struct Release {
  std::string modelId;
  std::string version;  // MAJOR.MINOR.PATCH
  std::string url;      // the firmware image
  uint32_t size = 0;
  std::string sha256;     // of the image, lowercase hex
  int minBatteryPct = 0;  // not below this
  int rolloutPercent = 100;
  std::string signature;  // ECDSA P-256 over signedText(), r || s, lowercase hex
};

// The exact text the signature covers (docs/ota.md); tools/firmware/release.ts signs the same.
std::string signedText(const Release& r);

// <0, 0 or >0, like strcmp, for MAJOR.MINOR.PATCH. Anything after the numbers (e.g.
// "-dev") is ignored. A version that doesn't start with three numbers sorts first.
int compareVersions(const std::string& a, const std::string& b);

// 0–99, the same for a frame every time: a rollout of n % reaches buckets below n.
int rolloutBucket(const std::string& hwId);

// What a release means for this frame. The image is installed only on `install`.
enum class Decision : uint8_t {
  install,
  upToDate,    // not newer than the running firmware
  otherModel,  // for another kind of frame
  notYet,      // outside the rollout so far
  lowBattery,
  gaveUp,  // this version already failed to start here twice
};

// failedTries: how many times this version was installed here without keeping itself.
Decision decide(const Release& r, const std::string& runningVersion, const std::string& modelId, const std::string& hwId,
                int batteryPct, int failedTries, bool ignoreRollout = false);

const char* toString(Decision d);

constexpr int kMaxTries = 2;

}  // namespace fwupdate
