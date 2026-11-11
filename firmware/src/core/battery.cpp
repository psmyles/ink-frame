#include "battery.h"

namespace battery {

namespace {

struct Point {
  int mv;
  int pct;
};

// Seeed's curve for the reTerminal E10xx battery (its ESPHome cookbook,
// wiki.seeedstudio.com/reterminal_e10xx_with_esphome_advanced), highest first;
// straight lines in between. The top is 4.15 V rather than 4.2 V so that a
// just-charged battery, which settles a little below the charger's 4.2 V, shows 100.
constexpr Point kCurve[] = {
    {4150, 100}, {3960, 90}, {3910, 80}, {3850, 70}, {3800, 60}, {3750, 50},
    {3680, 40},  {3580, 30}, {3490, 20}, {3410, 10}, {3300, 5},  {3270, 0},
};
constexpr int kPoints = sizeof(kCurve) / sizeof(kCurve[0]);

}  // namespace

int percentFromMillivolts(int mv) {
  if (mv >= kCurve[0].mv) return 100;
  for (int i = 1; i < kPoints; i++) {
    const Point hi = kCurve[i - 1], lo = kCurve[i];
    if (mv >= lo.mv) {
      const int span = hi.mv - lo.mv;
      return lo.pct + ((mv - lo.mv) * (hi.pct - lo.pct) + span / 2) / span;  // rounded
    }
  }
  return 0;
}

}  // namespace battery
