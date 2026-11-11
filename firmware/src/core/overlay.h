// What the frame draws over a photo (PLAN.md §9.4): its battery, as a thin line along
// the bottom or a small number in the bottom-left corner, chosen by the owner.
// Pure logic: no Arduino, tested on the computer (test/test_overlay).
#pragma once
#include <stdint.h>

namespace overlay {

// `battery_display` (openapi.yaml).
enum class Battery : uint8_t { bar, number };

// "number" → the number; anything else, or none (an older backend) → the bar.
Battery parseBattery(const char* s);

// The bar: how many pixels from the left show the charge left (pct clamped to 0–100).
int barLength(int width, int pct);

// The number: whether the photo under a box is dark, so the digits go white (else
// black). pixels holds one palette index per pixel, width × height, row by row;
// brightness[i] is how bright index i looks on the panel (0–255), for `colours`
// indices (others are skipped). The box is clipped to the image. Dark means the mean
// brightness is below threshold; an empty box isn't dark.
bool darkUnder(const uint8_t* pixels, int width, int height, int x, int y, int w, int h,
               const uint8_t* brightness, uint8_t colours, uint8_t threshold);

}  // namespace overlay
