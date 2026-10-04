// Battery and deep sleep (PLAN.md §9.2).
#pragma once
#include <Arduino.h>

namespace power {

int batteryPercent();

enum class Wake : uint8_t { powerOn, timer, green, white };
Wake wakeReason();
// After a white-button wake: the left one (previous photo in order).
bool leftWhiteHeld();

// How long the green button is held, up to limitMs (it's read right after waking).
uint32_t greenHeldMs(uint32_t limitMs);

// Sleeps for the given seconds, or until a button is pressed.
[[noreturn]] void deepSleep(uint32_t seconds);

}  // namespace power
