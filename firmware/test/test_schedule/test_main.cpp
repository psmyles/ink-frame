// When the frame changes the photo, checks for new photos and wakes (PLAN.md §9.4).
#include <unity.h>

#include "core/schedule.h"

using namespace schedule;

static const int32_t H = 3600;

static Settings quiet22to7() {
  Settings s;
  s.quietStart = 22 * H;
  s.quietEnd = 7 * H;
  return s;
}

void setUp() {}
void tearDown() {}

void test_quiet_hours_across_midnight() {
  const Settings s = quiet22to7();
  TEST_ASSERT_FALSE(inQuiet(s, 21 * H + 59 * 60));
  TEST_ASSERT_TRUE(inQuiet(s, 22 * H));
  TEST_ASSERT_TRUE(inQuiet(s, 3 * H));
  TEST_ASSERT_FALSE(inQuiet(s, 7 * H));
  TEST_ASSERT_EQUAL_UINT32(9 * H, untilQuietEnd(s, 22 * H));
  TEST_ASSERT_EQUAL_UINT32(4 * H, untilQuietEnd(s, 3 * H));
  TEST_ASSERT_EQUAL_UINT32(0, untilQuietEnd(s, 12 * H));
}

void test_quiet_hours_within_a_day_and_none() {
  Settings s;
  s.quietStart = 13 * H;
  s.quietEnd = 15 * H;
  TEST_ASSERT_TRUE(inQuiet(s, 14 * H));
  TEST_ASSERT_FALSE(inQuiet(s, 16 * H));
  TEST_ASSERT_FALSE(inQuiet(Settings{}, 14 * H));
  s.quietEnd = s.quietStart;  // same time: no quiet hours
  TEST_ASSERT_FALSE(inQuiet(s, 13 * H));
}

void test_backoff_doubles_up_to_the_interval() {
  TEST_ASSERT_EQUAL_UINT32(1 * H, backoffS(86400, 1));
  TEST_ASSERT_EQUAL_UINT32(2 * H, backoffS(86400, 2));
  TEST_ASSERT_EQUAL_UINT32(4 * H, backoffS(86400, 3));
  TEST_ASSERT_EQUAL_UINT32(16 * H, backoffS(86400, 5));
  TEST_ASSERT_EQUAL_UINT32(24 * H, backoffS(86400, 6));
  TEST_ASSERT_EQUAL_UINT32(24 * H, backoffS(86400, 200));
  TEST_ASSERT_EQUAL_UINT32(2 * H, backoffS(2 * H, 9));
}

void test_parse_hhmm() {
  TEST_ASSERT_EQUAL_INT32(22 * H, parseHhmm("22:00"));
  TEST_ASSERT_EQUAL_INT32(7 * H + 30 * 60, parseHhmm("07:30"));
  TEST_ASSERT_EQUAL_INT32(-1, parseHhmm(nullptr));
  TEST_ASSERT_EQUAL_INT32(-1, parseHhmm(""));
  TEST_ASSERT_EQUAL_INT32(-1, parseHhmm("24:00"));
  TEST_ASSERT_EQUAL_INT32(-1, parseHhmm("7:3"));
}

void test_a_change_in_quiet_hours_waits_for_their_end() {
  const Settings s = quiet22to7();
  const Now now{1000000, 20 * H, true};
  // Next photo due at 23:00 → moved to 07:00 (11 h from now).
  TEST_ASSERT_EQUAL_INT64(now.epoch + 11 * H, outOfQuiet(s, now, now.epoch + 3 * H));
  // Without a known time (no NTP yet), quiet hours can't apply.
  const Now unknown{1000000, 20 * H, false};
  TEST_ASSERT_EQUAL_INT64(unknown.epoch + 3 * H, outOfQuiet(s, unknown, unknown.epoch + 3 * H));
}

void test_sleep_until_the_earlier_of_photo_and_check() {
  Settings s = quiet22to7();
  s.imageIntervalS = 4 * H;
  const Now now{1000000, 12 * H, true};
  TEST_ASSERT_EQUAL_UINT32(4 * H, sleepSeconds(s, now, now.epoch + 4 * H, now.epoch + 10 * H));
  TEST_ASSERT_EQUAL_UINT32(2 * H, sleepSeconds(s, now, now.epoch + 4 * H, now.epoch + 2 * H));
  // At 20:00 the 4-hour change would be at midnight, in quiet hours: the check at 06:00 comes first.
  const Now evening{1000000, 20 * H, true};
  TEST_ASSERT_EQUAL_UINT32(10 * H, sleepSeconds(s, evening, evening.epoch + 4 * H, evening.epoch + 10 * H));
  // Never less than a minute, never more than the check interval.
  TEST_ASSERT_EQUAL_UINT32(60, sleepSeconds(s, now, now.epoch - 5, now.epoch + 10 * H));
  TEST_ASSERT_EQUAL_UINT32(s.syncIntervalS, sleepSeconds(s, now, now.epoch + 99 * H, now.epoch + 99 * H));
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_quiet_hours_across_midnight);
  RUN_TEST(test_quiet_hours_within_a_day_and_none);
  RUN_TEST(test_backoff_doubles_up_to_the_interval);
  RUN_TEST(test_parse_hhmm);
  RUN_TEST(test_a_change_in_quiet_hours_waits_for_their_end);
  RUN_TEST(test_sleep_until_the_earlier_of_photo_and_check);
  return UNITY_END();
}
