// The photo list, the cache on the card, what fits, and which photo comes next.
#include <unity.h>

#include "core/manifest.h"

using namespace manifest;

static const std::string A = "3f1c9a52-8d0e-4b7a-9c61-2a5e0f4d7b18";
static const std::string B = "7a0d2e44-1b3c-4f5e-8a9b-0c1d2e3f4a5b";
static const std::string C = "c0ffee00-1b3c-4f5e-8a9b-0c1d2e3f4a5b";
static const std::string SHA = "9b74c9897bac770ffc029102a200c5de9b74c9897bac770ffc029102a200c5de";

static std::vector<Image> three() {
  return {{A, SHA, 100, 1.0}, {B, SHA, 200, 2.0}, {C, SHA, 300, 3.5}};
}

void setUp() {}
void tearDown() {}

void test_line_round_trip() {
  Image img{A, SHA, 61234, 1.5}, back;
  TEST_ASSERT_TRUE(parseLine(toLine(img), back));
  TEST_ASSERT_EQUAL_STRING(A.c_str(), back.id.c_str());
  TEST_ASSERT_EQUAL_UINT32(61234, back.bytes);
  TEST_ASSERT_EQUAL_DOUBLE(1.5, back.position);
  TEST_ASSERT_TRUE(parseLine(toLine(img) + "\r", back));  // written on Windows
}

void test_bad_lines_are_skipped() {
  Image out;
  TEST_ASSERT_FALSE(parseLine("", out));
  TEST_ASSERT_FALSE(parseLine("not-a-uuid " + SHA + " 1 1", out));
  TEST_ASSERT_FALSE(parseLine(A + " abc 1 1", out));
  TEST_ASSERT_FALSE(parseLine(A + " " + SHA + " 0 1", out));
  TEST_ASSERT_FALSE(parseLine(A + " " + SHA + " 12x 1", out));
  TEST_ASSERT_FALSE(parseLine(A + " " + SHA + " 12 1 extra", out));
}

void test_photos_are_spread_over_folders() {
  TEST_ASSERT_EQUAL_STRING("/cache/3f", shardDir(A).c_str());
  TEST_ASSERT_EQUAL_STRING(("/cache/3f/" + A + ".png").c_str(), imagePath(A).c_str());
}

void test_downloads_stop_at_the_reserve_and_skip_what_does_not_fit() {
  const auto images = three();
  // 450 bytes free, 100 reserved: A (100) and B (200) fit; C (300) doesn't.
  auto plan = planDownloads(images, {false, false, false}, 450, 100);
  TEST_ASSERT_EQUAL(2, plan.download.size());
  TEST_ASSERT_EQUAL(1, plan.skipped.size());
  TEST_ASSERT_EQUAL(2, plan.skipped[0]);
  // A smaller photo later in the list still gets the room left over.
  plan = planDownloads(images, {false, false, false}, 420, 100);
  TEST_ASSERT_EQUAL(2, plan.download.size());  // A (100) + B (200) = 300 of 320
  plan = planDownloads(images, {true, false, false}, 400, 100);
  TEST_ASSERT_EQUAL(1, plan.download.size());  // B; C doesn't fit in the 100 left
  TEST_ASSERT_EQUAL(1, plan.download[0]);
  // A card fuller than the reserve: nothing.
  plan = planDownloads(images, {false, false, false}, 50, 100);
  TEST_ASSERT_EQUAL(0, plan.download.size());
  TEST_ASSERT_EQUAL(3, plan.skipped.size());
}

void test_new_photos_first_then_in_order() {
  const auto images = three();
  std::vector<std::string> newest{B, C};  // C arrived last: shown first
  PickState st;
  TEST_ASSERT_EQUAL(2, pickNext(images, newest, st, true, false, 0));
  TEST_ASSERT_EQUAL(1, pickNext(images, newest, st, true, false, 0));
  TEST_ASSERT_TRUE(newest.empty());
  TEST_ASSERT_EQUAL(2, pickNext(images, newest, st, true, false, 0));  // after B comes C
  TEST_ASSERT_EQUAL(0, pickNext(images, newest, st, true, false, 0));  // wraps
  TEST_ASSERT_EQUAL(2, pickNext(images, newest, st, true, true, 0));   // previous wraps back
}

void test_shuffle_never_repeats_the_last_photo() {
  const auto images = three();
  std::vector<std::string> newest;
  PickState st;
  st.lastId = B;
  for (uint32_t r = 0; r < 20; r++) {
    PickState s = st;
    const int i = pickNext(images, newest, s, false, false, r);
    TEST_ASSERT_NOT_EQUAL(1, i);
  }
  std::vector<Image> one{images[0]};
  TEST_ASSERT_EQUAL(0, pickNext(one, newest, st, false, false, 7));
  std::vector<Image> none;
  TEST_ASSERT_EQUAL(-1, pickNext(none, newest, st, false, false, 7));
}

void test_a_deleted_new_photo_is_passed_over() {
  const auto images = three();
  std::vector<std::string> newest{A, "gone0000-0000-0000-0000-000000000000"};
  PickState st;
  TEST_ASSERT_EQUAL(0, pickNext(images, newest, st, true, false, 0));
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_line_round_trip);
  RUN_TEST(test_bad_lines_are_skipped);
  RUN_TEST(test_photos_are_spread_over_folders);
  RUN_TEST(test_downloads_stop_at_the_reserve_and_skip_what_does_not_fit);
  RUN_TEST(test_new_photos_first_then_in_order);
  RUN_TEST(test_shuffle_never_repeats_the_last_photo);
  RUN_TEST(test_a_deleted_new_photo_is_passed_over);
  return UNITY_END();
}
