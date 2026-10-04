// Logs go to the serial port (USB-C, 115200). Console replies start with "@ " so a
// program on the other end can tell them apart (README.md).
#pragma once
#include <Arduino.h>

#define LOGF(...) Serial.printf(__VA_ARGS__)
#define LOGLN(s) Serial.println(s)
