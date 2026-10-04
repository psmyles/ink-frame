// Seeed reTerminal E1002 (PLAN.md §9.2): ESP32-S3, 8 MB PSRAM, 32 MB flash, 7.3"
// E Ink Spectra 6 (800 x 480), microSD on the display's SPI bus, 2000 mAh battery.
// Pins from the E1002 schematic, as in reference/ink-frame-lab/firmware.
#pragma once

// ePaper (SPI)
#define EPD_SCK_PIN 7
#define EPD_MOSI_PIN 9
#define EPD_CS_PIN 10
#define EPD_DC_PIN 11
#define EPD_RES_PIN 12
#define EPD_BUSY_PIN 13

// microSD (shares the SPI bus with the display)
#define SD_MISO_PIN 8
#define SD_CS_PIN 14
#define SD_DET_PIN 15  // LOW = card inserted
#define SD_EN_PIN 16   // power for the card slot

// Battery
#define BATTERY_ADC_PIN 1
#define BATTERY_ENABLE_PIN 21

// Buttons (active LOW, internal pull-up)
#define GREEN_BUTTON 3
#define WHITE_BUTTON_RIGHT 4
#define WHITE_BUTTON_LEFT 5

#define SCREEN_WIDTH 800
#define SCREEN_HEIGHT 480

#define BATTERY_FULL_VOLTAGE 4.2f
#define BATTERY_EMPTY_VOLTAGE 3.0f
#define VOLTAGE_DIVIDER_RATIO 2.0f
#define ADC_REFERENCE_VOLTAGE 3.3f
#define ADC_RESOLUTION 4095.0f
