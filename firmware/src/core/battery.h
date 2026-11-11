// The battery's charge from its voltage (PLAN.md §9.2).
// Pure logic: no Arduino, tested on the computer (test/test_battery).
#pragma once

namespace battery {

// Percent (0–100) left in a single-cell Li-Po at this voltage, in millivolts, as the
// frame measures it on waking (light load, close to resting). Not a straight line: the
// cell gives most of its charge between about 3.5 and 3.95 V, and the E1002 keeps
// working down to about 3.3 V. 4.15 V and up (just charged, or on USB) is 100.
int percentFromMillivolts(int mv);

}  // namespace battery
