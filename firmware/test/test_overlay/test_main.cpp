// The battery over a photo (PLAN.md §9.4): bar or number, and black or white digits.
#include <unity.h>

#include <vector>

#include "core/overlay.h"

using namespace overlay;

// Two colours: index 0 dark, index 1 light, like the panel's black and white.
static const uint8_t kBrightness[] = {40, 200};
static const uint8_t kThreshold = 120;

static bool dark(const std::vector<uint8_t>& px, int w, int h, int x, int y, int bw, int bh) {
  return darkUnder(px.data(), w, h, x, y, bw, bh, kBrightness, 2, kThreshold);
}

void setUp() {}
void tearDown() {}

void test_parse_battery_display() {
  TEST_ASSERT_TRUE(parseBattery("number") == Battery::number);
  TEST_ASSERT_TRUE(parseBattery("bar") == Battery::bar);
  TEST_ASSERT_TRUE(parseBattery(nullptr) == Battery::bar);  // an older backend sends none
  TEST_ASSERT_TRUE(parseBattery("pie") == Battery::bar);
  TEST_ASSERT_TRUE(parseBattery("") == Battery::bar);
}

void test_bar_length() {
  TEST_ASSERT_EQUAL_INT(0, barLength(800, 0));
  TEST_ASSERT_EQUAL_INT(584, barLength(800, 73));
  TEST_ASSERT_EQUAL_INT(800, barLength(800, 100));
  TEST_ASSERT_EQUAL_INT(0, barLength(800, -1));
  TEST_ASSERT_EQUAL_INT(800, barLength(800, 140));
}

void test_digits_go_white_over_a_dark_corner() {
  const int w = 40, h = 20;
  std::vector<uint8_t> px(w * h, 1);  // light everywhere
  TEST_ASSERT_FALSE(dark(px, w, h, 2, 10, 20, 9));
  for (int y = 8; y < h; y++) {
    for (int x = 0; x < 24; x++) px[y * w + x] = 0;  // a dark bottom-left corner
  }
  TEST_ASSERT_TRUE(dark(px, w, h, 2, 10, 20, 9));
  TEST_ASSERT_FALSE(dark(px, w, h, 26, 10, 10, 9));  // the light part next to it
}

void test_dithered_grey_uses_the_mean() {
  const int w = 10, h = 10;
  std::vector<uint8_t> px(w * h);
  // 3 of 4 dark: mean 80, dark. 1 of 4 dark: mean 160, light.
  for (int i = 0; i < w * h; i++) px[i] = i % 4 == 0 ? 1 : 0;
  TEST_ASSERT_TRUE(dark(px, w, h, 0, 0, w, h));
  for (int i = 0; i < w * h; i++) px[i] = i % 4 == 0 ? 0 : 1;
  TEST_ASSERT_FALSE(dark(px, w, h, 0, 0, w, h));
}

void test_box_is_clipped_to_the_photo() {
  const int w = 10, h = 10;
  std::vector<uint8_t> px(w * h, 0);
  TEST_ASSERT_TRUE(dark(px, w, h, -1, 5, 4, 8));    // past the left and bottom edges
  TEST_ASSERT_FALSE(dark(px, w, h, 20, 20, 4, 4));  // entirely off the photo: not dark
  TEST_ASSERT_FALSE(darkUnder(nullptr, w, h, 0, 0, 4, 4, kBrightness, 2, kThreshold));
}

void test_unknown_colours_are_skipped() {
  const int w = 4, h = 1;
  std::vector<uint8_t> px = {0, 9, 9, 9};  // one dark pixel, the rest out of range
  TEST_ASSERT_TRUE(dark(px, w, h, 0, 0, w, h));
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_parse_battery_display);
  RUN_TEST(test_bar_length);
  RUN_TEST(test_digits_go_white_over_a_dark_corner);
  RUN_TEST(test_dithered_grey_uses_the_mean);
  RUN_TEST(test_box_is_clipped_to_the_photo);
  RUN_TEST(test_unknown_colours_are_skipped);
  return UNITY_END();
}
