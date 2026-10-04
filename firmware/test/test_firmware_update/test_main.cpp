// Firmware updates: versions, rollout buckets, the signed text and the decision.
#include <unity.h>

#include "core/firmware_update.h"

using namespace fwupdate;

static Release release() {
  Release r;
  r.modelId = "reterminal-e1002";
  r.version = "0.2.0";
  r.url = "https://psmyles.github.io/ink-frame/firmware/reterminal-e1002/0.2.0.bin";
  r.size = 1310720;
  r.sha256 = "9b74c9897bac770ffc029102a200c5de9b74c9897bac770ffc029102a200c5de";
  r.minBatteryPct = 30;
  r.rolloutPercent = 100;
  return r;
}

void setUp() {}
void tearDown() {}

void test_versions_compare_by_number() {
  TEST_ASSERT_TRUE(compareVersions("0.10.0", "0.9.9") > 0);
  TEST_ASSERT_TRUE(compareVersions("1.0.0", "0.99.99") > 0);
  TEST_ASSERT_TRUE(compareVersions("0.2.0", "0.2.1") < 0);
  TEST_ASSERT_EQUAL(0, compareVersions("0.2.0", "0.2.0"));
  TEST_ASSERT_EQUAL(0, compareVersions("0.2.0-dev", "0.2.0"));  // the suffix doesn't count
  TEST_ASSERT_TRUE(compareVersions("junk", "0.0.1") < 0);
  TEST_ASSERT_TRUE(compareVersions("0.0.1", "") > 0);
}

void test_rollout_bucket_is_stable_and_spread() {
  TEST_ASSERT_EQUAL(rolloutBucket("e1002-24ec4a1b1a2b"), rolloutBucket("e1002-24ec4a1b1a2b"));
  int below50 = 0;
  for (int i = 0; i < 1000; i++) {
    const int b = rolloutBucket("e1002-" + std::to_string(100000 + i * 7919));
    TEST_ASSERT_TRUE(b >= 0 && b < 100);
    if (b < 50) below50++;
  }
  TEST_ASSERT_INT_WITHIN(80, 500, below50);
}

// tools/firmware/release.ts signs exactly this text (its test checks the same string).
void test_signed_text() {
  TEST_ASSERT_EQUAL_STRING(
      "inkframe-firmware 1\n"
      "model reterminal-e1002\n"
      "version 0.2.0\n"
      "url https://psmyles.github.io/ink-frame/firmware/reterminal-e1002/0.2.0.bin\n"
      "size 1310720\n"
      "sha256 9b74c9897bac770ffc029102a200c5de9b74c9897bac770ffc029102a200c5de\n"
      "min_battery_pct 30\n"
      "rollout_percent 100\n",
      signedText(release()).c_str());
}

void test_decide() {
  const Release r = release();
  const std::string model = "reterminal-e1002", hw = "e1002-24ec4a1b1a2b";
  TEST_ASSERT_EQUAL(Decision::install, decide(r, "0.1.0", model, hw, 80, 0));
  TEST_ASSERT_EQUAL(Decision::upToDate, decide(r, "0.2.0", model, hw, 80, 0));
  TEST_ASSERT_EQUAL(Decision::upToDate, decide(r, "0.3.0", model, hw, 80, 0));  // never back
  TEST_ASSERT_EQUAL(Decision::otherModel, decide(r, "0.1.0", "other-7-3", hw, 80, 0));
  TEST_ASSERT_EQUAL(Decision::lowBattery, decide(r, "0.1.0", model, hw, 29, 0));
  TEST_ASSERT_EQUAL(Decision::install, decide(r, "0.1.0", model, hw, 80, 1));
  TEST_ASSERT_EQUAL(Decision::gaveUp, decide(r, "0.1.0", model, hw, 80, 2));

  Release partial = r;
  partial.rolloutPercent = rolloutBucket(hw);  // just misses this frame
  TEST_ASSERT_EQUAL(Decision::notYet, decide(partial, "0.1.0", model, hw, 80, 0));
  TEST_ASSERT_EQUAL(Decision::install, decide(partial, "0.1.0", model, hw, 80, 0, true));
  partial.rolloutPercent = rolloutBucket(hw) + 1;
  TEST_ASSERT_EQUAL(Decision::install, decide(partial, "0.1.0", model, hw, 80, 0));
  partial.rolloutPercent = 0;  // paused
  TEST_ASSERT_EQUAL(Decision::notYet, decide(partial, "0.1.0", model, hw, 80, 0));
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_versions_compare_by_number);
  RUN_TEST(test_rollout_bucket_is_stable_and_spread);
  RUN_TEST(test_signed_text);
  RUN_TEST(test_decide);
  return UNITY_END();
}
