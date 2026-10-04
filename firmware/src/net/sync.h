// A check for new photos: POST /device-api/sync, then mirror the photo list into the
// cache exactly (PLAN.md §9.4, openapi.yaml). Wi-Fi must be on.
#pragma once
#include <Arduino.h>

#include "config/nvs_settings.h"

namespace photos {

enum class Result : uint8_t { ok, removed, failed };

struct Report {
  int added = 0, deleted = 0, skipped = 0, failed = 0, total = 0;
};

// fullList asks for every photo (manifest_version 0), e.g. after the card was swapped.
Result sync(Config& cfg, int batteryPct, bool fullList, Report& report);

}  // namespace photos
