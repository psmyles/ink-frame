#include "schedule.h"

namespace schedule {

static int32_t mod(int64_t a, int32_t m) { return static_cast<int32_t>(((a % m) + m) % m); }

bool inQuiet(const Settings& s, int32_t t) {
  if (!s.hasQuiet()) return false;
  t = mod(t, kDay);
  if (s.quietStart < s.quietEnd) return t >= s.quietStart && t < s.quietEnd;
  return t >= s.quietStart || t < s.quietEnd;  // crosses midnight, e.g. 22:00–07:00
}

uint32_t untilQuietEnd(const Settings& s, int32_t t) {
  if (!inQuiet(s, t)) return 0;
  return static_cast<uint32_t>(mod(static_cast<int64_t>(s.quietEnd) - mod(t, kDay), kDay));
}

uint32_t backoffS(uint32_t syncIntervalS, uint8_t failures) {
  uint64_t b = 3600;
  for (uint8_t i = 1; i < failures && b < syncIntervalS; i++) b *= 2;
  return static_cast<uint32_t>(b < syncIntervalS ? b : syncIntervalS);
}

int32_t parseHhmm(const char* s) {
  if (!s) return -1;
  int h = 0, m = 0, i = 0;
  for (; s[i] >= '0' && s[i] <= '9' && i < 2; i++) h = h * 10 + (s[i] - '0');
  if (i == 0 || s[i] != ':') return -1;
  int j = i + 1, k = 0;
  for (; s[j] >= '0' && s[j] <= '9' && k < 2; j++, k++) m = m * 10 + (s[j] - '0');
  if (k != 2 || h > 23 || m > 59) return -1;
  return h * 3600 + m * 60;
}

int64_t outOfQuiet(const Settings& s, const Now& now, int64_t at) {
  if (!now.timeKnown || !s.hasQuiet()) return at;
  const int32_t secondOfDayAt = mod(now.secondOfDay + (at - now.epoch), kDay);
  return at + untilQuietEnd(s, secondOfDayAt);
}

uint32_t sleepSeconds(const Settings& s, const Now& now, int64_t nextImageAt, int64_t nextSyncAt) {
  int64_t wake = outOfQuiet(s, now, nextImageAt);
  if (nextSyncAt < wake) wake = nextSyncAt;
  int64_t d = wake - now.epoch;
  if (d < 60) d = 60;
  if (d > s.syncIntervalS) d = s.syncIntervalS;
  return static_cast<uint32_t>(d);
}

}  // namespace schedule
