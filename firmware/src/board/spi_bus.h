// The SPI bus the display and the memory card share.
#pragma once
#include <SPI.h>

SPIClass& spiBus();
// Sets up the pins and chip selects; before using the card or the display.
void initSpiBus();
