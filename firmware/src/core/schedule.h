// When to change the photo, check for new photos, and wake up (PLAN.md §9.4).
// Pure logic: no Arduino, tested on the computer (test/test_schedule).
#pragma once
#include <stdint.h>

namespace schedule {

constexpr uint32_t kDay = 86400;

struct Settings {
  uint32_t imageIntervalS = 14400;
  uint32_t syncIntervalS = 86400;
  // Quiet hours, as seconds after local midnight; -1 = none. They may cross midnight.
  int32_t quietStart = -1;
  int32_t quietEnd = -1;

  bool hasQuiet() const { return quietStart >= 0 && quietEnd >= 0 && quietStart != quietEnd; }
};

// Whether a local time of day (seconds after midnight) is in the quiet hours.
bool inQuiet(const Settings& s, int32_t secondOfDay);

// Seconds from secondOfDay until the quiet hours end (0 when not in them).
uint32_t untilQuietEnd(const Settings& s, int32_t secondOfDay);

// After a failed check: 1 h, 2 h, 4 h … capped at the check interval.
uint32_t backoffS(uint32_t syncIntervalS, uint8_t failures);

// "HH:MM" → seconds after midnight; -1 for null, empty or malformed.
int32_t parseHhmm(const char* s);

struct Now {
  int64_t epoch;          // Unix seconds
  int32_t secondOfDay;    // local, from the frame's time zone
  bool timeKnown;         // false before the first NTP sync after power-on
};

// Pushes a photo change that falls in the quiet hours to the end of them.
int64_t outOfQuiet(const Settings& s, const Now& now, int64_t at);

// When to wake next: the earlier of the next photo change (out of the quiet hours) and
// the next check. At least 60 s, at most the check interval.
uint32_t sleepSeconds(const Settings& s, const Now& now, int64_t nextImageAt, int64_t nextSyncAt);

}  // namespace schedule
