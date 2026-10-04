#include "spi_bus.h"

#include <Arduino.h>

#include "e1002.h"

static SPIClass hspi(HSPI);

SPIClass& spiBus() { return hspi; }

void initSpiBus() {
  pinMode(EPD_RES_PIN, OUTPUT);
  pinMode(EPD_DC_PIN, OUTPUT);
  pinMode(EPD_CS_PIN, OUTPUT);
  digitalWrite(EPD_CS_PIN, HIGH);  // display deselected
  hspi.begin(EPD_SCK_PIN, SD_MISO_PIN, EPD_MOSI_PIN, -1);
}
