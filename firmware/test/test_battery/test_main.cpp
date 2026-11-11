// The battery's charge from its voltage (PLAN.md §9.2).
#include <unity.h>

#include "core/battery.h"

using battery::percentFromMillivolts;

void setUp() {}
void tearDown() {}

void test_full_battery_is_100() {
  TEST_ASSERT_EQUAL_INT(100, percentFromMillivolts(4150));  // just charged, settled
  TEST_ASSERT_EQUAL_INT(100, percentFromMillivolts(4200));  // on the charger
  TEST_ASSERT_EQUAL_INT(100, percentFromMillivolts(4400));
}

void test_empty_battery_is_0() {
  TEST_ASSERT_EQUAL_INT(0, percentFromMillivolts(3270));
  TEST_ASSERT_EQUAL_INT(0, percentFromMillivolts(3000));
  TEST_ASSERT_EQUAL_INT(0, percentFromMillivolts(0));  // no reading
  TEST_ASSERT_EQUAL_INT(0, percentFromMillivolts(-5));
}

void test_points_on_the_curve() {
  TEST_ASSERT_EQUAL_INT(90, percentFromMillivolts(3960));
  TEST_ASSERT_EQUAL_INT(50, percentFromMillivolts(3750));
  TEST_ASSERT_EQUAL_INT(20, percentFromMillivolts(3490));  // the app's default warning
  TEST_ASSERT_EQUAL_INT(5, percentFromMillivolts(3300));
}

void test_between_points_is_rounded() {
  TEST_ASSERT_EQUAL_INT(95, percentFromMillivolts(4055));  // halfway 3960–4150
  TEST_ASSERT_EQUAL_INT(55, percentFromMillivolts(3775));  // halfway 3750–3800
  TEST_ASSERT_EQUAL_INT(97, percentFromMillivolts(4100));  // 90 + 140/190 × 10 = 97.4
  TEST_ASSERT_EQUAL_INT(12, percentFromMillivolts(3422));  // 11.5; an E1002 still running
}

void test_never_goes_down_as_voltage_rises() {
  int last = percentFromMillivolts(3000);
  for (int mv = 3001; mv <= 4300; mv++) {
    const int pct = percentFromMillivolts(mv);
    TEST_ASSERT_TRUE(pct >= last);
    TEST_ASSERT_TRUE(pct >= 0 && pct <= 100);
    last = pct;
  }
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_full_battery_is_100);
  RUN_TEST(test_empty_battery_is_0);
  RUN_TEST(test_points_on_the_curve);
  RUN_TEST(test_between_points_is_rounded);
  RUN_TEST(test_never_goes_down_as_voltage_rises);
  return UNITY_END();
}
