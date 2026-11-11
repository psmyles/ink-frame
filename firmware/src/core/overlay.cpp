#include "overlay.h"

#include <string.h>

namespace overlay {

Battery parseBattery(const char* s) { return s && strcmp(s, "number") == 0 ? Battery::number : Battery::bar; }

int barLength(int width, int pct) {
  if (pct < 0) pct = 0;
  if (pct > 100) pct = 100;
  return width * pct / 100;
}

bool darkUnder(const uint8_t* pixels, int width, int height, int x, int y, int w, int h,
               const uint8_t* brightness, uint8_t colours, uint8_t threshold) {
  if (!pixels) return false;
  const int x0 = x < 0 ? 0 : x, y0 = y < 0 ? 0 : y;
  const int x1 = x + w > width ? width : x + w, y1 = y + h > height ? height : y + h;
  uint32_t sum = 0, count = 0;
  for (int row = y0; row < y1; row++) {
    const uint8_t* p = pixels + row * width;
    for (int col = x0; col < x1; col++) {
      if (p[col] >= colours) continue;
      sum += brightness[p[col]];
      count++;
    }
  }
  return count > 0 && sum < static_cast<uint32_t>(threshold) * count;
}

}  // namespace overlay
